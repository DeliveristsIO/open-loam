# demo/test/open_loam_webhook_test.rb
require "test_helper"

# Webhooks: a tenant declares where its events go; every matching event becomes
# a ledger row in the publishing transaction and a job after commit. Nothing
# here touches the network.
class OpenLoamWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-hooks")
    @krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-hooks")
  end

  teardown { OpenLoam::Webhooks.reset_configuration! }

  test "a trailing dot matches a whole domain, anything else is one exact event" do
    with_tenant(@warsaw) do
      domain = OpenLoam::WebhookEndpoint.create!(url: "https://example.test/all", event_pattern: "rental.")
      exact = OpenLoam::WebhookEndpoint.create!(url: "https://example.test/one", event_pattern: "rental.equipment.created")

      assert domain.matches?("rental.equipment.created")
      assert domain.matches?("rental.damage_report.submit")
      refute domain.matches?("billing.penalty.due")
      assert exact.matches?("rental.equipment.created")
      refute exact.matches?("rental.equipment.updated")
    end
  end

  test "an endpoint is created with a signing secret and active by default" do
    with_tenant(@warsaw) do
      endpoint = OpenLoam::WebhookEndpoint.create!(url: "https://example.test/hook", event_pattern: "rental.")
      assert endpoint.active?
      assert endpoint.secret.present?
      refute OpenLoam::WebhookEndpoint.new(url: "not-a-url", event_pattern: "rental.").valid?
    end
  end

  test "a domain event writes one ledger row per matching active endpoint and enqueues its job" do
    with_tenant(@warsaw) do
      matching = OpenLoam::WebhookEndpoint.create!(url: "https://example.test/all", event_pattern: "rental.")
      OpenLoam::WebhookEndpoint.create!(url: "https://example.test/billing", event_pattern: "billing.")
      OpenLoam::WebhookEndpoint.create!(url: "https://example.test/off", event_pattern: "rental.", active: false)

      assert_enqueued_jobs 1, only: OpenLoam::WebhookDeliveryJob do
        Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
      end

      delivery = OpenLoam::WebhookDelivery.sole
      assert_equal matching.id, delivery.endpoint_id
      assert_equal "rental.equipment.created", delivery.event_name
      assert_equal "Equipment", delivery.payload_hash["type"]
      assert_equal [ @warsaw.id, delivery.id ], enqueued_jobs.last[:args]
    end
  end

  test "endpoints that receive the same event share its event id" do
    with_tenant(@warsaw) do
      2.times { |i| OpenLoam::WebhookEndpoint.create!(url: "https://example.test/#{i}", event_pattern: "rental.") }
      Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
      assert_equal 1, OpenLoam::WebhookDelivery.distinct.count(:event_id)
      assert_equal 2, OpenLoam::WebhookDelivery.distinct.count(:delivery_id)
    end
  end

  test "a rolled-back transaction leaves no row and no job" do
    with_tenant(@warsaw) do
      OpenLoam::WebhookEndpoint.create!(url: "https://example.test/all", event_pattern: "rental.")
      assert_no_enqueued_jobs only: OpenLoam::WebhookDeliveryJob do
        ActiveRecord::Base.transaction do
          OpenLoam::Events.publish("rental.equipment.inspected", { id: 1 })
          raise ActiveRecord::Rollback
        end
      end
      assert_equal 0, OpenLoam::WebhookDelivery.count
    end
  end

  test "another tenant's endpoints never see this tenant's events" do
    with_tenant(@krakow) { OpenLoam::WebhookEndpoint.create!(url: "https://example.test/krakow", event_pattern: "rental.") }
    with_tenant(@warsaw) do
      assert_no_enqueued_jobs only: OpenLoam::WebhookDeliveryJob do
        Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
      end
    end
  end

  test "the delivery body carries event, payload and tenant" do
    body = OpenLoam::WebhookDeliveryJob.body_for("rental.equipment.created", { "id" => 7 }, 3)
    assert_equal({ "event" => "rental.equipment.created", "payload" => { "id" => 7 }, "tenant_id" => 3 }, JSON.parse(body))
  end

  test "the signature is HMAC-SHA256 of the exact body under the endpoint's secret" do
    # A fixed vector: if the algorithm, the digest encoding or the header format
    # ever changes, every receiver in the world breaks — so pin it.
    assert_equal "sha256=d42927434049e0b8c73ce887062238cc1c6bb6644bfe66e66d8dd0f30b85679e",
                 OpenLoam::WebhookDeliveryJob.signature("s3cr3t", '{"a":1}')
  end

  test "the job delivers a ledger row through the configured transport" do
    sent = []
    OpenLoam::Webhooks.transport = Class.new do
      define_singleton_method(:post) do |url, body:, headers:, timeout:|
        sent << [ url, JSON.parse(body) ]
        OpenLoam::Webhooks::Response.new(code: 200, headers: {}, excerpt: "", duration_ms: 1)
      end
    end
    delivery = with_tenant(@warsaw) do
      endpoint = OpenLoam::WebhookEndpoint.create!(url: "https://example.test/hook", event_pattern: "rental.")
      endpoint.deliveries.create!(event_id: "e1", event_name: "rental.equipment.created", payload: { "id" => 7 })
    end

    OpenLoam::WebhookDeliveryJob.perform_now(@warsaw.id, delivery.id)

    assert_equal [ [ "https://example.test/hook", { "event" => "rental.equipment.created", "payload" => { "id" => 7 }, "tenant_id" => @warsaw.id } ] ], sent
    with_tenant(@warsaw) { assert_equal "succeeded", delivery.reload.status }
  end

  test "a job enqueued by 0.3.0 (endpoint id, event, payload) still delivers once" do
    OpenLoam::Webhooks.transport = Class.new do
      def self.post(*, **) = OpenLoam::Webhooks::Response.new(code: 200, headers: {}, excerpt: "", duration_ms: 1)
    end
    endpoint_id = with_tenant(@warsaw) { OpenLoam::WebhookEndpoint.create!(url: "https://example.test/hook", event_pattern: "rental.").id }

    OpenLoam::WebhookDeliveryJob.perform_now(@warsaw.id, endpoint_id, "rental.equipment.created", { "id" => 8 })

    with_tenant(@warsaw) do
      delivery = OpenLoam::WebhookDelivery.sole
      assert_equal "succeeded", delivery.status
      assert_equal({ "id" => 8 }, delivery.payload_hash)
    end
  end

  test "a delivery for a tenant that no longer exists is dropped" do
    assert_nothing_raised { OpenLoam::WebhookDeliveryJob.perform_now(0, 0) }
    assert_nothing_raised { OpenLoam::WebhookDeliveryJob.perform_now(0, 0, "rental.equipment.created", { "id" => 7 }) }
  end

  test "send_test! and redeliver! create or reset a row and enqueue it" do
    OpenLoam::Webhooks.test_event_name = "acme.webhook.test"
    with_tenant(@warsaw) do
      endpoint = OpenLoam::WebhookEndpoint.create!(url: "https://example.test/hook", event_pattern: "rental.")
      test_delivery = nil
      assert_enqueued_with(job: OpenLoam::WebhookDeliveryJob) { test_delivery = OpenLoam::Webhooks.send_test!(endpoint) }
      assert_equal "acme.webhook.test", test_delivery.event_name
      assert_equal true, test_delivery.payload_hash["test"]

      test_delivery.update!(status: "failed", attempts: 3, next_attempt_at: 1.hour.from_now)
      assert_enqueued_with(job: OpenLoam::WebhookDeliveryJob, args: [ @warsaw.id, test_delivery.id ]) do
        OpenLoam::Webhooks.redeliver!(test_delivery)
      end
      assert_equal "pending", test_delivery.reload.status
      assert_nil test_delivery.next_attempt_at
      assert_equal 0, test_delivery.attempts
    end
  end

  test "redeliver! on a sending row changes nothing and enqueues no job" do
    with_tenant(@warsaw) do
      endpoint = OpenLoam::WebhookEndpoint.create!(url: "https://example.test/hook", event_pattern: "rental.")
      delivery = endpoint.deliveries.create!(event_id: SecureRandom.uuid, event_name: "rental.x", payload: {})
      delivery.update!(status: "sending", attempts: 2, sending_at: Time.current)
      assert_no_enqueued_jobs { OpenLoam::Webhooks.redeliver!(delivery) }
      delivery.reload
      assert_equal "sending", delivery.status
      assert_equal 2, delivery.attempts
      assert_not_nil delivery.sending_at
    end
  end
end
