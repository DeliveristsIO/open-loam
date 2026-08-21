# Scheduler (recurring jobs)


Recurring jobs, per tenant. `Loam::Scheduler.register(key:, job_class:, schedule:,
scope:)` at file scope (materialized by `sync_tenant` in `on_tenant_created`), or
add one at `/admin/scheduled_jobs`. `schedule` is cron (`0 7 * * *`) or
`interval:N`; `scope` "tenant" (enqueues `tenant_id:`) or "system" (once);
`job_class` MUST be a real ActiveJob (validated). `bin/rails loam:scheduler:tick`
(system cron) fires due ones with an atomic no-double-fire claim.

