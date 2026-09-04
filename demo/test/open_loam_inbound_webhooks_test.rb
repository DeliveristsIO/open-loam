require "test_helper"

# L-710: receiving webhooks FROM external systems. Verify-before-parse, HMAC over
# the raw body, replay-resistant via a (source, external_id) ledger, published
# onto the event bus. Uniform 401 for every auth failure so a sender can't probe
# which check failed. Exercised through OpenLoam::InboundWebhooks.ingest (no HTTP).
class OpenLoamInboundWebhooksTest < ActiveSupport::TestCase
  SECRET = "shhh-secret-key".freeze

  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-inbound")
    @source = with_tenant(@warsaw) do
      OpenLoam::InboundWebhookSource.create!(name: "Acme", secret: SECRET, event_name: "demo.inbound.received")
    end
  end

  def sign(body, secret = SECRET)
    "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, body)
  end

  def ingest(body, headers, token: @source.token)
    OpenLoam::InboundWebhooks.ingest(token: token, raw_body: body, headers: headers)
  ensure
    OpenLoam::Current.reset
  end

  def deliveries
    with_tenant(@warsaw) { OpenLoam::InboundWebhookDelivery.count }
  end

  test "a valid signature is accepted, recorded, and published on the bus" do
    body = %({"id":7})
    received = []
    sub = OpenLoam::Events.subscribe("demo.inbound.received") { |_n, payload| received << payload }
    result = ingest(body, { "X-OpenLoam-Signature" => sign(body) })
    ActiveSupport::Notifications.unsubscribe(sub)

    assert_equal 202, result.status
    with_tenant(@warsaw) do
      delivery = OpenLoam::InboundWebhookDelivery.sole
      assert_equal "received", delivery.status
      assert_equal 7, delivery.payload_hash["id"]
    end
    assert_equal 1, received.size
    assert_equal @source.id, received.first[:source_id]
  end

  test "a bad signature is rejected 401 and records nothing" do
    body = %({"id":7})
    assert_equal 401, ingest(body, { "X-OpenLoam-Signature" => sign(body, "wrong-key") }).status
    assert_equal 0, deliveries
  end

  test "a wrong-length signature is 401, never a 500" do
    body = %({"id":7})
    assert_equal 401, ingest(body, { "X-OpenLoam-Signature" => "sha256=short" }).status
    assert_equal 401, ingest(body, { "X-OpenLoam-Signature" => "" }).status
    assert_equal 401, ingest(body, {}).status
  end

  test "an unknown or inactive source is 404 (before any signature work)" do
    body = %({"id":7})
    assert_equal 404, ingest(body, { "X-OpenLoam-Signature" => sign(body) }, token: "nope").status

    with_tenant(@warsaw) { @source.update!(active: false) }
    assert_equal 404, ingest(body, { "X-OpenLoam-Signature" => sign(body) }).status
  end

  test "a body over the size cap is 413 before anything else" do
    big = "x" * (OpenLoam::InboundWebhooks::MAX_BYTES + 1)
    assert_equal 413, ingest(big, { "X-OpenLoam-Signature" => sign(big) }).status
    assert_equal 0, deliveries
  end

  test "a replay (same external_id) is idempotent — 200, one row, published once" do
    body = %({"id":7})
    publishes = 0
    sub = OpenLoam::Events.subscribe("demo.inbound.received") { |_n, _p| publishes += 1 }

    first = ingest(body, { "X-OpenLoam-Signature" => sign(body) })   # body-hash external_id
    second = ingest(body, { "X-OpenLoam-Signature" => sign(body) })
    ActiveSupport::Notifications.unsubscribe(sub)

    assert_equal 202, first.status
    assert_equal 200, second.status
    assert_equal 1, deliveries
    assert_equal 1, publishes
  end

  test "the delivery-id header dedupes even when bodies differ" do
    with_tenant(@warsaw) { @source.update!(delivery_id_header: "X-Delivery-Id") }
    a = ingest(%({"n":1}), { "X-OpenLoam-Signature" => sign(%({"n":1})), "X-Delivery-Id" => "abc" })
    b = ingest(%({"n":2}), { "X-OpenLoam-Signature" => sign(%({"n":2})), "X-Delivery-Id" => "abc" })

    assert_equal 202, a.status
    assert_equal 200, b.status
    assert_equal 1, deliveries
  end

  test "a configured timestamp header enforces a freshness window" do
    with_tenant(@warsaw) { @source.update!(timestamp_header: "X-Timestamp", timestamp_tolerance: 300) }
    body = %({"id":7})

    stale = (Time.current.to_i - 10_000).to_s
    assert_equal 401, ingest(body, { "X-OpenLoam-Signature" => sign(body), "X-Timestamp" => stale }).status

    fresh = Time.current.to_i.to_s
    assert_equal 202, ingest(body, { "X-OpenLoam-Signature" => sign(body), "X-Timestamp" => fresh }).status
  end

  test "a publish failure rolls the delivery row back (retry-safe)" do
    body = %({"id":7})
    sub = OpenLoam::Events.subscribe("demo.inbound.received") { |_n, _p| raise "subscriber blew up" }

    assert_raises(RuntimeError) { ingest(body, { "X-OpenLoam-Signature" => sign(body) }) }
    ActiveSupport::Notifications.unsubscribe(sub)

    assert_equal 0, deliveries, "no half-written ledger row survives a failed publish"
  end
end
