module Loam
  # A recurring job that runs on a schedule (cron or interval). Tenant-scoped:
  # a "tenant"-scope schedule enqueues its job in this tenant on schedule; a
  # "system"-scope schedule enqueues once with no tenant context. Audited on
  # config changes (not per run — runs are tracked by last_run_at/next_run_at).
  #
  # SECURITY: job_class is validated to be a known ActiveJob (see
  # Loam::Scheduler.resolve_job_class) at save AND at enqueue — a scheduler that
  # constantized and ran arbitrary user input would be a code-execution hole.
  class ScheduledJob < Loam::TenantRecord
    self.table_name = "loam_scheduled_jobs"

    include Loam::Auditable

    SCOPES = %w[tenant system].freeze
    LOCK_TTL = 5.minutes    # how long a claim holds a due job before another tick may retry it
    STALE_LOCK = LOCK_TTL

    validates :key, presence: true, uniqueness: { scope: :tenant_id }
    validates :name, :schedule, presence: true
    validates :scope, inclusion: { in: SCOPES }
    validate :job_class_is_a_known_job

    scope :active, -> { where(active: true) }

    # The next fire time strictly after `from`, in this job's timezone (UTC when
    # unset). Stored in next_run_at as UTC.
    def compute_next_run(from = Time.current)
      Loam::Cron.next_after(schedule, from: from, zone: timezone.presence || "UTC")
    end

    def job_class_constant
      Loam::Scheduler.resolve_job_class(job_class)
    end

    private

    def job_class_is_a_known_job
      errors.add(:job_class, "must name a known ActiveJob") unless job_class_constant
    end
  end
end
