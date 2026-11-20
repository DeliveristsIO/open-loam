require "test_helper"

class OpenLoamWebhookEndpointTest < ActiveSupport::TestCase
  setup do
    @tenant = OpenLoam::Tenant.create!(name: "Branch Gdansk", slug: "gdansk-hooks")
  end

  teardown { OpenLoam::Webhooks.reset_configuration! }

  def endpoint(**attrs)
    OpenLoam::WebhookEndpoint.create!({ url: "https://example.test/hook", event_pattern: "rental." }.merge(attrs))
  end

  test "event_patterns lets one endpoint follow several events; event_pattern still works alone" do
    with_tenant(@tenant) do
      many = endpoint(event_pattern: nil, event_patterns: %w[rental.equipment.created billing.])
      assert many.matches?("rental.equipment.created")
      assert many.matches?("billing.penalty.due")
      refute many.matches?("rental.equipment.updated")

      single = endpoint
      assert_equal [ "rental." ], single.patterns
      refute OpenLoam::WebhookEndpoint.new(url: "https://example.test/x", event_pattern: nil, event_patterns: []).valid?
    end
  end

  test "secrets are stored in plaintext by default and sealed when encrypt_secrets is on" do
    with_tenant(@tenant) do
      plain = endpoint
      assert_match(/\A\h{64}\z/, plain.read_attribute(:secret))

      OpenLoam::Webhooks.encrypt_secrets = true
      sealed = endpoint
      assert sealed.read_attribute(:secret).start_with?("v2:")
      assert_match(/\A\h{64}\z/, sealed.reload.secret)
      assert_match(/\A\h{64}\z/, plain.reload.secret, "a plaintext row stays readable after switching encryption on")
    end
  end

  test "rotation keeps the old secret valid for the grace period" do
    with_tenant(@tenant) do
      hook = endpoint
      old = hook.secret
      now = Time.current
      new_secret = hook.rotate_secret!(now: now)

      assert_not_equal old, new_secret
      assert_equal [ new_secret, old ], hook.signing_secrets(now + 1.hour)
      assert_equal [ new_secret ], hook.signing_secrets(now + 25.hours)
    end
  end

  test "consecutive failures disable the endpoint once and publish an event; a success resets the count" do
    OpenLoam::Webhooks.disable_after_failures = 3
    events = []
    subscription = OpenLoam::Events.subscribe("open_loam.webhook.") { |name, payload| events << [ name, payload ] }

    with_tenant(@tenant) do
      hook = endpoint
      2.times { hook.record_failure! }
      hook.record_success!
      assert_equal 0, hook.reload.consecutive_failures

      3.times { hook.record_failure! }
      hook.reload
      refute hook.active?
      assert_equal "consecutive_failures", hook.disabled_reason
      hook.record_failure!
      assert_equal 1, events.count { |name, _| name == "open_loam.webhook.endpoint_disabled" }
      assert_equal hook.id, events.last.last[:endpoint_id]

      hook.enable!
      assert hook.reload.active?
      assert_nil hook.disabled_reason
      assert_equal 0, hook.consecutive_failures
    end
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
  end

  test "a delivery gets a public delivery id and is removed with its endpoint" do
    with_tenant(@tenant) do
      hook = endpoint
      delivery = hook.deliveries.create!(event_id: SecureRandom.uuid, event_name: "rental.equipment.created", payload: { "id" => 1 })
      assert_match(/\Awhd_\h{24}\z/, delivery.delivery_id)
      assert_equal "pending", delivery.status
      assert_equal({ "id" => 1 }, delivery.payload_hash)

      hook.destroy!
      assert_not OpenLoam::WebhookDelivery.exists?(delivery.id)
    end
  end
end
