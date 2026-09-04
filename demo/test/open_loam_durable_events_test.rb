require "test_helper"

# Durable event subscribers (Loam::DurableEvents) — the persistent twin of the
# in-process Loam::Events.subscribe. The contract under test: a published event
# is PERSISTED as a Loam::EventDelivery row in its tenant, delivered by a job with
# retry (at-least-once, unordered), and parked `dead` past MAX_ATTEMPTS. Row state
# — not the queue — is the durable record, so the sweep can redeliver a lost job.
class LoamDurableEventsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-durable")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-durable")
    DurableEventEcho.reset!
    # A subscriber whose handler always fails — for the retry/dead-letter path.
    Loam::DurableEvents.register(key: "t706_boom", to: "t706boom.",
                                 call: ->(_name, _payload) { raise "handler failed" })
  end

  test "a published event persists one pending delivery per matching durable subscriber, in its tenant" do
    with_tenant(@warsaw) do
      assert_enqueued_jobs 1, only: Loam::EventDeliveryJob do
        Loam::Events.publish("demo.thing.happened", { id: 42 })
      end

      delivery = Loam::EventDelivery.sole
      assert_equal "demo_echo", delivery.subscriber_key
      assert_equal "demo.thing.happened", delivery.event_name
      assert_equal "pending", delivery.status
      assert_equal "42", delivery.payload_hash["id"].to_s
    end

    assert_equal 0, with_tenant(@krakow) { Loam::EventDelivery.count }, "delivery rows are tenant-scoped"
  end

  test "running the delivery job invokes the handler and marks the row delivered" do
    id = with_tenant(@warsaw) do
      Loam::Events.publish("demo.thing.happened", { id: 7 })
      Loam::EventDelivery.sole.id
    end

    perform_enqueued_jobs

    assert_equal 1, DurableEventEcho.received.size
    assert_equal "demo.thing.happened", DurableEventEcho.received.first[:event]
    assert_equal "delivered", with_tenant(@warsaw) { Loam::EventDelivery.find(id).status }
  end

  test "an event with no matching durable subscriber persists nothing" do
    with_tenant(@warsaw) do
      assert_no_enqueued_jobs only: Loam::EventDeliveryJob do
        Loam::Events.publish("unmatched.thing.happened", { id: 1 })
      end
      assert_equal 0, Loam::EventDelivery.count
    end
  end

  test "a failing handler retries with backoff, then parks the row dead after MAX_ATTEMPTS" do
    with_tenant(@warsaw) do
      Loam::Events.publish("t706boom.thing.happened", { id: 1 })
      delivery = Loam::EventDelivery.sole
      base = Time.current

      # Each attempt fails; the row stays pending with next_attempt_at pushed out.
      # Advance `now` past the backoff gate each time.
      (Loam::DurableEvents::MAX_ATTEMPTS - 1).times do |i|
        Loam::DurableEvents.deliver(delivery.reload, now: base + (i * 1.day))
        assert_equal "pending", delivery.reload.status
        assert delivery.next_attempt_at.present?
      end

      Loam::DurableEvents.deliver(delivery.reload, now: base + 999.days)
      assert_equal "dead", delivery.reload.status
      assert_equal Loam::DurableEvents::MAX_ATTEMPTS, delivery.attempts
      assert_match "handler failed", delivery.last_error
    end
  end

  test "a delivery whose subscriber is unknown at delivery time is parked dead, never executed" do
    with_tenant(@warsaw) do
      delivery = Loam::EventDelivery.create!(subscriber_key: "gone-since-enqueue",
                                             event_name: "x.y.z", payload: {}, status: "pending")
      Loam::DurableEvents.deliver(delivery)

      assert_equal "dead", delivery.reload.status
      assert_match "no registered subscriber", delivery.last_error
    end
  end

  test "the job no-ops when the row is not visible yet (async adapter racing the txn) or gone" do
    assert_nothing_raised { Loam::EventDeliveryJob.perform_now(@warsaw.id, 0) }
    assert_nothing_raised { Loam::EventDeliveryJob.perform_now(0, 0) }
  end

  test "the sweep re-enqueues only due pending rows" do
    with_tenant(@warsaw) do
      Loam::EventDelivery.create!(subscriber_key: "demo_echo", event_name: "demo.a.b", payload: {}, status: "pending")
      Loam::EventDelivery.create!(subscriber_key: "demo_echo", event_name: "demo.a.b", payload: {}, status: "delivered", delivered_at: Time.current)
      Loam::EventDelivery.create!(subscriber_key: "demo_echo", event_name: "demo.a.b", payload: {}, status: "pending", next_attempt_at: 1.hour.from_now)

      assert_enqueued_jobs 1, only: Loam::EventDeliveryJob do
        assert_equal 1, Loam::DurableEvents.redeliver_stuck
      end
    end
  end

  test "delivering an already-delivered row is a no-op (at-least-once tolerance)" do
    with_tenant(@warsaw) do
      delivery = Loam::EventDelivery.create!(subscriber_key: "demo_echo", event_name: "demo.a.b",
                                             payload: {}, status: "delivered", delivered_at: Time.current)
      Loam::DurableEvents.deliver(delivery)

      assert_equal 0, DurableEventEcho.received.size
      assert_equal "delivered", delivery.reload.status
    end
  end
end
