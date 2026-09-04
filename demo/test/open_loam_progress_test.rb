require "test_helper"

# OpenLoam::Progress / OpenLoam::ProgressJob: long-running task progress, pushed live over
# the SSE bridge. Tested WITHOUT sleeps or live sockets — the API and the event
# frame directly, like the L-908 event-stream tests.
class OpenLoamProgressTest < ActiveSupport::TestCase
  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-prog")
    @krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-prog")
    @actor = User.create!(name: "Anna", email: "anna@example.test", password: "password")
  end

  test "start creates a running job in the current tenant, stamped with the actor" do
    with_tenant(@warsaw, actor: @actor) do
      job = OpenLoam::Progress.start(name: "Reindex", total: 50)
      assert job.running?
      assert_equal 0, job.completed
      assert_equal 50, job.total
      assert_equal @actor.id, job.actor_id
      assert job.started_at
    end
  end

  test "advance increments completed and computes percent" do
    with_tenant(@warsaw) do
      job = OpenLoam::Progress.start(name: "x", total: 4)
      job.advance
      assert_equal 1, job.completed
      assert_equal 25, job.percent
      job.advance(by: 3, message: "done batch")
      assert_equal 4, job.completed
      assert_equal 100, job.percent
      assert_equal "done batch", job.message
    end
  end

  test "advance throttles the broadcast to once per whole percent, not per tick" do
    events = []
    sub = OpenLoam::Events.subscribe("open_loam.progress.updated") { |_name, payload| events << payload }
    with_tenant(@warsaw) do
      job = OpenLoam::Progress.start(name: "x", total: 200)
      10.times { job.advance }  # 200-item job: a percent point is every 2 ticks

      assert_equal 10, job.reload.completed
      assert_equal 5, job.percent
      assert_equal 5, events.size, "one broadcast per percent (5), not one per tick (10)"
    end
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  test "complete! / fail! / cancel! set a terminal status and finished_at" do
    with_tenant(@warsaw) do
      done = OpenLoam::Progress.start(name: "a", total: 10)
      done.complete!
      assert_equal "completed", done.status
      assert_equal 10, done.completed, "complete! fills the bar"
      assert done.finished_at

      broke = OpenLoam::Progress.start(name: "b", total: 10)
      broke.fail!("disk full")
      assert_equal "failed", broke.status
      assert_equal "disk full", broke.error
      assert broke.finished_at

      stopped = OpenLoam::Progress.start(name: "c", total: 10)
      stopped.cancel!
      assert_equal "cancelled", stopped.status
      assert stopped.finished_at
    end
  end

  test "cancelled? sees a cancel made elsewhere, so a job can stop cooperatively" do
    with_tenant(@warsaw) do
      job = OpenLoam::Progress.start(name: "x", total: 10)
      refute job.cancelled?

      # Simulate an admin cancelling in another request (a separate instance).
      OpenLoam::ProgressJob.find(job.id).cancel!
      assert job.cancelled?, "re-reads the status column, not the stale in-memory copy"
    end
  end

  test "stale? flags a running job whose heartbeat went quiet" do
    with_tenant(@warsaw) do
      fresh = OpenLoam::Progress.start(name: "fresh", total: 10)
      refute fresh.stale?

      old = OpenLoam::Progress.start(name: "old", total: 10)
      old.update_column(:updated_at, 10.minutes.ago)
      assert old.reload.stale?

      old.complete!
      refute old.stale?, "a finished job is never stale"
    end
  end

  test "a progress job is invisible from another tenant" do
    with_tenant(@warsaw) { OpenLoam::Progress.start(name: "warsaw-only", total: 10) }
    with_tenant(@krakow) { assert_equal 0, OpenLoam::ProgressJob.count }
  end

  test "the progress event is broadcastable and its SSE frame carries only safe fields" do
    original = OpenLoam.broadcast_events
    OpenLoam.broadcast_events = [ "open_loam.progress." ]

    assert OpenLoam::EventStream.broadcastable?("open_loam.progress.updated")
    frame = OpenLoam::EventStream.frame("open_loam.progress.updated",
                                    { id: 7, percent: 50, status: "running", message: "leaky detail", tenant_id: 3 })
    data = JSON.parse(frame[/data: (.+)/, 1])
    assert_equal({ "id" => 7, "percent" => 50, "status" => "running" }, data, "message/tenant_id never reach the browser")
  ensure
    OpenLoam.broadcast_events = original
  end
end

# The Tasks admin screen (Admin::ProgressJobsController).
class OpenLoamProgressAdminTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @tenant = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-prog-admin")
    @user = User.create!(name: "Tomek", email: "tomek@example.test", password: "password")
    with_tenant(@tenant) { OpenLoam::Membership.create!(user: @user, role: "employee") }
    post admin_session_path, params: { email: "tomek@example.test", password: "password" }
  end

  test "the tasks list renders a job with its bar" do
    with_tenant(@tenant) { OpenLoam::Progress.start(name: "Reindex", total: 10).advance(by: 5) }

    get admin_progress_jobs_path

    assert_response :success
    assert_match "Reindex", response.body
    assert_select "#progress-fill-#{with_tenant(@tenant) { OpenLoam::ProgressJob.first.id }}"
  end

  test "run enqueues the demo job" do
    assert_enqueued_with(job: DemoProgressJob) do
      post run_admin_progress_jobs_path
    end
    assert_redirected_to admin_progress_jobs_path
  end

  test "cancel stops a running job" do
    job = with_tenant(@tenant, actor: @user) { OpenLoam::Progress.start(name: "x", total: 10) } # owner may cancel

    post cancel_admin_progress_job_path(job)

    assert_redirected_to admin_progress_jobs_path
    assert_equal "cancelled", with_tenant(@tenant) { job.reload.status }
  end
end
