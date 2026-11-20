# demo/test/open_loam_webhook_sweep_test.rb
require "test_helper"

class OpenLoamWebhookSweepTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @now = Time.zone.parse("2026-11-20 12:00:00")
    @tenant = OpenLoam::Tenant.create!(name: "Branch Poznan", slug: "poznan-hooks")
    @quiet = OpenLoam::Tenant.create!(name: "Branch Opole", slug: "opole-hooks")
    with_tenant(@tenant) do
      @endpoint = OpenLoam::WebhookEndpoint.create!(url: "https://example.test/hook", event_pattern: "rental.")
    end
  end

  teardown { OpenLoam::Webhooks.reset_configuration! }

  def row(**attrs)
    with_tenant(@tenant) do
      @endpoint.deliveries.create!({ event_id: SecureRandom.uuid, event_name: "rental.equipment.created", payload: {} }.merge(attrs))
    end
  end

  test "lost, overdue and stuck rows are re-enqueued; fresh and future rows are left alone" do
    lost = row(created_at: @now - 5.minutes)
    overdue = row(next_attempt_at: @now - 1.second, attempts: 2)
    stuck = row(status: "sending", sending_at: @now - 10.minutes, attempts: 1)
    fresh = row(created_at: @now - 10.seconds)
    future = row(next_attempt_at: @now + 1.hour, attempts: 1)

    enqueued = with_tenant(@tenant) { OpenLoam::Webhooks.sweep(now: @now) }

    assert_equal 3, enqueued
    ids = enqueued_jobs.select { |job| job[:job] == OpenLoam::WebhookDeliveryJob }.map { |job| job[:args].last }
    assert_equal [ lost.id, overdue.id, stuck.id ].sort, ids.sort
    with_tenant(@tenant) { assert_equal "pending", stuck.reload.status }
    refute_includes ids, fresh.id
    refute_includes ids, future.id
  end

  test "final rows older than the retention are pruned" do
    old = row(status: "succeeded", updated_at: @now - 31.days)
    recent = row(status: "failed", updated_at: @now - 1.day)
    with_tenant(@tenant) do
      OpenLoam::Webhooks.sweep(now: @now)
      refute OpenLoam::WebhookDelivery.exists?(old.id)
      assert OpenLoam::WebhookDelivery.exists?(recent.id)
    end
  end

  test "the fan-out job only visits tenants with work" do
    row(created_at: @now - 5.minutes)
    travel_to(@now) do
      assert_equal [ @tenant.id ], OpenLoam::Webhooks.tenant_ids_needing_sweep
      assert_enqueued_with(job: OpenLoam::WebhookSweepJob, args: [ { tenant_id: @tenant.id } ]) do
        OpenLoam::WebhookSweepJob.perform_now
      end
    end
  end

  test "the sweep is registered with the scheduler" do
    assert(OpenLoam::Scheduler.registered.any? { |entry| entry[:key] == "open_loam_webhook_sweep" })
  end
end
