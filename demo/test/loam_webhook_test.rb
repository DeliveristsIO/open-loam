require "test_helper"

# Webhooks: a tenant declares where its events should go, and every matching
# event turns into a signed HTTP delivery — enqueued as a job, never sent
# inline. Nothing here touches the network.
class LoamWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # Lets the delivery path be exercised without HTTP: everything up to the
  # request is the real job, only the send is replaced.
  class RecordingDeliveryJob < Loam::WebhookDeliveryJob
    def self.deliveries = @deliveries ||= []

    private

    def deliver(endpoint, body, event_name)
      self.class.deliveries << { endpoint_id: endpoint.id, body: body, event: event_name }
    end
  end

  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-hooks")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-hooks")
    @anna = User.create!(name: "Anna")
    with_tenant(@warsaw) { Loam::Membership.create!(user: @anna, role: "manager") }

    RecordingDeliveryJob.deliveries.clear
  end

  test "a trailing dot matches a whole domain, anything else is one exact event" do
    with_tenant(@warsaw) do
      domain = Loam::WebhookEndpoint.create!(url: "https://example.test/all", event_pattern: "rental.")
      exact = Loam::WebhookEndpoint.create!(url: "https://example.test/one",
                                           event_pattern: "rental.equipment.created")

      assert domain.matches?("rental.equipment.created")
      assert domain.matches?("rental.damage_report.submit")
      refute domain.matches?("billing.penalty.due")

      assert exact.matches?("rental.equipment.created")
      refute exact.matches?("rental.equipment.updated")
    end
  end

  test "an endpoint is created with a signing secret and active by default" do
    with_tenant(@warsaw) do
      endpoint = Loam::WebhookEndpoint.create!(url: "https://example.test/hook", event_pattern: "rental.")

      assert endpoint.active?
      assert endpoint.secret.present?
      refute Loam::WebhookEndpoint.new(url: "not-a-url", event_pattern: "rental.").valid?
    end
  end

  test "a domain event enqueues one delivery per matching active endpoint" do
    with_tenant(@warsaw) do
      matching = Loam::WebhookEndpoint.create!(url: "https://example.test/all", event_pattern: "rental.")
      Loam::WebhookEndpoint.create!(url: "https://example.test/billing", event_pattern: "billing.")
      Loam::WebhookEndpoint.create!(url: "https://example.test/off", event_pattern: "rental.", active: false)

      assert_enqueued_jobs 1, only: Loam::WebhookDeliveryJob do
        Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
      end

      tenant_id, endpoint_id, event_name, payload = enqueued_jobs.last[:args]
      assert_equal @warsaw.id, tenant_id
      assert_equal matching.id, endpoint_id
      assert_equal "rental.equipment.created", event_name
      assert_equal "Equipment", payload["type"]
    end
  end

  test "another tenant's endpoints never see this tenant's events" do
    with_tenant(@krakow) do
      Loam::WebhookEndpoint.create!(url: "https://example.test/krakow", event_pattern: "rental.")
    end

    with_tenant(@warsaw) do
      assert_no_enqueued_jobs only: Loam::WebhookDeliveryJob do
        Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
      end
    end
  end

  test "the delivery body carries event, payload and tenant" do
    body = Loam::WebhookDeliveryJob.body_for("rental.equipment.created", { "id" => 7 }, 3)

    assert_equal({ "event" => "rental.equipment.created", "payload" => { "id" => 7 }, "tenant_id" => 3 },
                 JSON.parse(body))
  end

  test "the signature is HMAC-SHA256 of the exact body under the endpoint's secret" do
    # A fixed vector: if the algorithm, the digest encoding or the header
    # format ever changes, every receiver in the world breaks — so pin it.
    assert_equal "sha256=d42927434049e0b8c73ce887062238cc1c6bb6644bfe66e66d8dd0f30b85679e",
                 Loam::WebhookDeliveryJob.signature("s3cr3t", '{"a":1}')
  end

  test "delivery sends the signed body for an active endpoint and skips an inactive one" do
    endpoint_id = with_tenant(@warsaw) do
      Loam::WebhookEndpoint.create!(url: "https://example.test/hook", event_pattern: "rental.").id
    end

    RecordingDeliveryJob.perform_now(@warsaw.id, endpoint_id, "rental.equipment.created", { "id" => 7 })

    assert_equal 1, RecordingDeliveryJob.deliveries.size
    delivered = RecordingDeliveryJob.deliveries.last
    assert_equal "rental.equipment.created", delivered[:event]
    assert_equal 7, JSON.parse(delivered[:body]).dig("payload", "id")

    with_tenant(@warsaw) { Loam::WebhookEndpoint.find(endpoint_id).update!(active: false) }
    RecordingDeliveryJob.perform_now(@warsaw.id, endpoint_id, "rental.equipment.created", { "id" => 8 })

    assert_equal 1, RecordingDeliveryJob.deliveries.size, "an endpoint switched off between enqueue and delivery is skipped"
  end

  test "a delivery for a tenant that no longer exists is dropped" do
    assert_nothing_raised do
      RecordingDeliveryJob.perform_now(0, 0, "rental.equipment.created", { "id" => 7 })
    end
    assert_empty RecordingDeliveryJob.deliveries
  end
end
