module Loam
  # Progress of a long-running job (a bulk import, a reindex, a report) so the
  # admin can watch it live instead of guessing. Tenant-scoped; a job started in
  # one tenant is only visible and streamable there.
  #
  # Deliberately NOT audited: progress is high-frequency churn (many `advance`
  # ticks) and the audit trail would fill with noise. The terminal status and
  # any error are captured on the row itself, which is the summary that matters.
  #
  # Each meaningful change publishes `loam.progress.updated` (broadcastable → SSE)
  # carrying only id/percent/status — no record contents. See Loam::Progress for
  # the entry point.
  class ProgressJob < Loam::TenantRecord
    self.table_name = "loam_progress_jobs"

    STATUSES = %w[running completed failed cancelled].freeze
    STALE_AFTER = 5.minutes

    validates :name, presence: true
    validates :status, inclusion: { in: STATUSES }

    scope :recent, -> { order(started_at: :desc, id: :desc) }

    # Integer 0..100. A zero total is treated as 0% (an unknown-size job).
    def percent
      return 0 if total.to_i <= 0

      [ (completed.to_f / total * 100).floor, 100 ].min
    end

    def running? = status == "running"
    def terminal? = !running?

    # Seconds remaining, extrapolated from the rate so far, or nil when it can't
    # be estimated yet (no progress, or already finished).
    def eta_seconds
      return nil unless running? && completed.to_i.positive? && started_at

      elapsed = Time.current - started_at
      rate = completed / elapsed # items per second
      return nil unless rate.positive?

      ((total - completed) / rate).round
    end

    # A running job whose process died leaves the row "running" forever; it is
    # stale once its heartbeat (updated_at, bumped on every advance) goes quiet.
    # The prototype exposes the predicate and a manual mark-failed; a reaper
    # daemon is the roadmap.
    def stale?
      running? && updated_at < STALE_AFTER.ago
    end

    # Increment progress. Persists every tick (so the count and heartbeat stay
    # current) but THROTTLES the SSE broadcast to once per whole percent (or a
    # message change) — a 10k-item job pushes ~100 frames, not 10k.
    def advance(by: 1, message: nil)
      before = percent
      self.completed = completed.to_i + by
      self.message = message if message
      save!
      broadcast if percent != before || message
      self
    end

    def complete!
      finish!("completed") { self.completed = total if total.to_i.positive? }
    end

    def fail!(error_message = nil)
      finish!("failed") { self.error = error_message.to_s.presence }
    end

    def cancel!
      finish!("cancelled")
    end

    # A cooperative cancel: a long job calls this periodically and stops early.
    # Re-reads the status column so an admin's cancel in ANOTHER request is seen
    # without clobbering the in-memory counters.
    def cancelled?
      self.class.where(id: id).pick(:status) == "cancelled"
    end

    private

    def finish!(new_status)
      yield if block_given?
      self.status = new_status
      self.finished_at = Time.current
      save!
      broadcast
      self
    end

    # Only ever id/percent/status leave the server (Loam::Events stamps tenant_id
    # for the SSE deliverable filter; the frame's safe_payload drops everything
    # else).
    def broadcast
      Loam::Events.publish("loam.progress.updated", id: id, percent: percent, status: status)
    end
  end
end
