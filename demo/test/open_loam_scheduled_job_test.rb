require "test_helper"

# Test-only jobs (real ActiveJob subclasses, so the whitelist accepts them).
class SchedTenantJob < ApplicationJob
  def perform(tenant_id:); end
end

class SchedSystemJob < ApplicationJob
  def perform; end
end

# OpenLoam::Cron: the stdlib next-run calculator.
class OpenLoamCronTest < ActiveSupport::TestCase
  test "computes the next run for cron and interval expressions, timezone-aware" do
    daily = OpenLoam::Cron.next_after("0 7 * * *", from: Time.utc(2026, 1, 1, 8, 0), zone: "UTC")
    assert_equal Time.utc(2026, 1, 2, 7, 0), daily

    quarter = OpenLoam::Cron.next_after("*/15 * * * *", from: Time.utc(2026, 1, 1, 12, 7), zone: "UTC")
    assert_equal Time.utc(2026, 1, 1, 12, 15), quarter

    monday = OpenLoam::Cron.next_after("0 9 * * 1", from: Time.utc(2026, 1, 1, 0, 0), zone: "UTC")
    assert_equal Time.utc(2026, 1, 5, 9, 0), monday, "next Monday 09:00"

    interval = OpenLoam::Cron.next_after("interval:3600", from: Time.utc(2026, 1, 1, 12, 0), zone: "UTC")
    assert_equal Time.utc(2026, 1, 1, 13, 0), interval

    warsaw = OpenLoam::Cron.next_after("0 7 * * *", from: Time.utc(2026, 1, 1, 0, 0), zone: "Europe/Warsaw")
    assert_equal Time.utc(2026, 1, 1, 6, 0), warsaw, "07:00 Warsaw (UTC+1 in winter) is 06:00 UTC"
  end

  test "rejects a malformed cron" do
    assert_raises(ArgumentError) { OpenLoam::Cron.next_after("nonsense", from: Time.current) }
    assert_raises(ArgumentError) { OpenLoam::Cron.next_after("0 7 * *", from: Time.current) }
  end
end

class OpenLoamSchedulerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @allowed = OpenLoam.schedulable_jobs
    OpenLoam.schedulable_jobs = %w[SchedTenantJob SchedSystemJob]  # allowlist the test jobs
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-sched")
    @krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-sched")
  end

  teardown { OpenLoam.schedulable_jobs = @allowed }

  def make_job(tenant, key:, job_class: "SchedTenantJob", scope: "tenant", due: true, active: true)
    with_tenant(tenant) do
      OpenLoam::ScheduledJob.create!(
        key: key, name: key, job_class: job_class, schedule: "0 3 * * *", scope: scope, active: active,
        next_run_at: due ? 1.minute.ago : 1.hour.from_now
      )
    end
  end

  test "a job_class that is not a known ActiveJob is refused (code-execution guard)" do
    with_tenant(@warsaw) do
      %w[Kernel User String NotARealClass].each do |bad|
        job = OpenLoam::ScheduledJob.new(key: "x", name: "x", job_class: bad, schedule: "0 0 * * *", scope: "tenant")
        refute job.valid?, "#{bad} must be refused"
        assert job.errors[:job_class].any?
      end
    end
  end

  test "tick enqueues only DUE schedules and advances next_run_at" do
    due = make_job(@warsaw, key: "due")
    make_job(@warsaw, key: "later", due: false)

    assert_enqueued_jobs 1, only: SchedTenantJob do
      OpenLoam::Scheduler.tick
    end
    assert with_tenant(@warsaw) { due.reload.next_run_at > Time.current }, "the fired job's next run advanced"
  end

  test "a tenant-scope job enqueues with its tenant, a system-scope job runs once with none" do
    make_job(@warsaw, key: "t", job_class: "SchedTenantJob", scope: "tenant")
    make_job(@warsaw, key: "s", job_class: "SchedSystemJob", scope: "system")

    OpenLoam::Scheduler.tick

    assert_enqueued_with(job: SchedTenantJob, args: [ { tenant_id: @warsaw.id } ])
    assert_enqueued_with(job: SchedSystemJob, args: [])
  end

  test "the atomic claim prevents a double-fire: a locked row is skipped, and a fired row is not due again" do
    make_job(@warsaw, key: "once")

    assert_equal 1, OpenLoam::Scheduler.tick, "fires once"
    assert_equal 0, OpenLoam::Scheduler.tick, "immediately after, next_run_at is in the future — not re-fired"

    # A row claimed by another worker (locked, future lock) is skipped.
    locked = make_job(@krakow, key: "locked")
    with_tenant(@krakow) { locked.update_columns(locked_until: 10.minutes.from_now) }
    assert_equal 0, OpenLoam::Scheduler.tick, "a locked due row is skipped"
  end

  test "a Warsaw schedule never runs in Krakow" do
    make_job(@warsaw, key: "warsaw-only")

    assert_enqueued_jobs 1, only: SchedTenantJob do
      OpenLoam::Scheduler.tick
    end
    assert_enqueued_with(job: SchedTenantJob, args: [ { tenant_id: @warsaw.id } ])
    enqueued = enqueued_jobs.select { |j| j[:job] == SchedTenantJob }
    assert enqueued.none? { |j| j[:args] == [ { "tenant_id" => @krakow.id } ] }, "no Krakow enqueue"
  end

  test "one failing job does not block the others (failure isolation)" do
    good = make_job(@warsaw, key: "good")
    bad = make_job(@warsaw, key: "bad")
    # Poison the job_class past validation to force an enqueue-time failure.
    with_tenant(@warsaw) { bad.update_column(:job_class, "NoLongerAClass") }

    fired = nil
    assert_nothing_raised { fired = OpenLoam::Scheduler.tick }
    assert_equal 1, fired, "only the good job fired"
    assert with_tenant(@warsaw) { good.reload.next_run_at > Time.current }, "the good job advanced"
    assert_nil with_tenant(@warsaw) { bad.reload.last_run_at }, "the bad job did not run"
    assert_nil with_tenant(@warsaw) { bad.reload.locked_until }, "the bad job's lock was released for a retry"
  end
end
