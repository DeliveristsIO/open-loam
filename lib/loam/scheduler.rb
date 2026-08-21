module Loam
  # Per-tenant recurring jobs. Modules self-register default schedules; an app
  # also creates them from the admin. A runner calls Loam::Scheduler.tick
  # periodically (wire `loam:scheduler:tick` to system cron — every minute) and
  # each DUE schedule enqueues its ActiveJob.
  #
  # NO DOUBLE-FIRE — the whole correctness story. tick ATOMICALLY CLAIMS due
  # jobs so two worker processes never enqueue the same one:
  #   * PostgreSQL: `SELECT ... FOR UPDATE SKIP LOCKED` — one worker wins each row.
  #   * SQLite (demo/harness): a transactional claim; SQLite serializes writers,
  #     which is correct for the single-process prototype.
  # The mechanism is behind `claim_due`, chosen per adapter. A claim also stamps
  # `locked_until` so a crashed worker's rows free themselves after LOCK_TTL.
  module Scheduler
    class UnknownJobError < Loam::Error; end

    class << self
      # --- declarative registry (like broadcast_events / feature_defaults) ---

      def register(key:, job_class:, schedule:, scope: "tenant", name: nil)
        registry[key.to_s] = {
          key: key.to_s, job_class: job_class.to_s, schedule: schedule.to_s,
          scope: scope.to_s, name: (name || key).to_s
        }
      end

      def registered = registry.values

      def reset_registry!
        @registry = {}
      end

      # Materialize the registered TENANT-scope schedules as rows in `tenant`
      # (idempotent — safe from on_tenant_created and `loam:sync`). System-scope
      # schedules are created explicitly by the app (they are not per-tenant).
      def sync_tenant(tenant)
        Loam.as_tenant(tenant) do
          registered.each do |default|
            next unless default[:scope] == "tenant"

            job = Loam::ScheduledJob.find_or_initialize_by(key: default[:key])
            job.name = default[:name]
            job.job_class = default[:job_class]
            job.schedule = default[:schedule]
            job.scope = "tenant"
            job.active = true if job.new_record?
            job.next_run_at ||= job.compute_next_run
            job.save!
          end
        end
      end

      # --- the tick ---

      # Claim and enqueue every due schedule. Returns how many fired. One job's
      # failure never blocks the others (its lock is released so a later tick
      # retries it).
      def tick(now: Time.current)
        fired = 0
        claim_due(now).each do |job|
          begin
            enqueue_target(job)
            job.update_columns(last_run_at: now, next_run_at: job.compute_next_run(now),
                               locked_until: nil, updated_at: now)
            fired += 1
          rescue StandardError => error
            job.update_columns(locked_until: nil, updated_at: now)
            logger&.error("[loam scheduler] #{job.key} failed: #{error.class}: #{error.message}")
          end
        end
        fired
      end

      # Enqueue a schedule's job right now without touching its schedule (the
      # admin "run now" button). Re-validates job_class.
      def run_now(job)
        enqueue_target(job)
      end

      # THE code-execution guard: a job_class must resolve to a real ActiveJob
      # subclass AND be ALLOWLISTED — either registered here or listed in
      # Loam.schedulable_jobs. "Any ActiveJob" would let a tenant admin schedule
      # ActiveStorage::PurgeJob, a mailer's delivery job, etc.
      def resolve_job_class(name)
        name = name.to_s
        return nil unless allowed_job_class?(name)

        klass = name.safe_constantize
        klass if klass.is_a?(Class) && defined?(ActiveJob::Base) && klass < ActiveJob::Base
      end

      def allowed_job_class?(name)
        registered.any? { |default| default[:job_class] == name } || Loam.schedulable_jobs.include?(name)
      end

      def resolve_job_class!(name)
        resolve_job_class(name) || raise(UnknownJobError, "#{name.inspect} is not a known ActiveJob")
      end

      private

      def registry
        @registry ||= {}
      end

      def enqueue_target(job)
        klass = resolve_job_class!(job.job_class)

        if job.scope == "system"
          klass.perform_later
        else
          # Carry the tenant explicitly (ActiveJob doesn't serialize Loam::Current),
          # and enqueue inside the tenant so any enqueue-time scoping is correct.
          Loam.as_tenant(job.tenant) { klass.perform_later(tenant_id: job.tenant_id) }
        end
      end

      # Atomically claim due, unlocked schedules across ALL tenants (a blessed
      # cross-tenant scan — the runner has no tenant context, like
      # Loam::Membership.tenants_for), stamping locked_until so a concurrent tick
      # skips them.
      def claim_due(now)
        lock_until = now + Loam::ScheduledJob::LOCK_TTL
        due = Loam::ScheduledJob.unscoped.active
                                .where("next_run_at <= ?", now)
                                .where("locked_until IS NULL OR locked_until < ?", now)

        claimed = []
        Loam::ScheduledJob.transaction do
          relation = postgres? ? due.lock("FOR UPDATE SKIP LOCKED") : due
          ids = relation.pluck(:id)
          break if ids.empty?

          Loam::ScheduledJob.unscoped.where(id: ids).update_all(locked_until: lock_until)
          claimed = Loam::ScheduledJob.unscoped.where(id: ids).to_a
        end
        claimed
      end

      def postgres?
        Loam::ScheduledJob.connection.adapter_name.to_s.downcase.include?("postgres")
      end

      def logger
        Rails.logger if defined?(Rails) && Rails.respond_to?(:logger)
      end
    end
  end
end
