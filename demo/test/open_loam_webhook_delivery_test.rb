# demo/test/open_loam_webhook_delivery_test.rb
require "test_helper"

class OpenLoamWebhookDeliveryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # Stands in for the network: records every request, answers from a script.
  class ScriptedTransport
    attr_reader :requests

    def initialize(*answers)
      @answers = answers
      @requests = []
    end

    def post(url, body:, headers:, timeout:)
      @requests << { url: url, body: body, headers: headers, timeout: timeout }
      answer = @answers.shift || 200
      raise answer if answer.is_a?(Exception)

      code, retry_after = Array(answer)
      OpenLoam::Webhooks::Response.new(code: code, headers: { "retry-after" => retry_after }, excerpt: "body #{code}", duration_ms: 7)
    end
  end

  setup do
    @tenant = OpenLoam::Tenant.create!(name: "Branch Lodz", slug: "lodz-hooks")
    @now = Time.zone.parse("2026-11-20 10:00:00")
    with_tenant(@tenant) do
      @endpoint = OpenLoam::WebhookEndpoint.create!(url: "https://example.test/hook", event_pattern: "rental.")
      @delivery = @endpoint.deliveries.create!(event_id: "evt-1", event_name: "rental.equipment.created", payload: { "id" => 7 })
    end
  end

  teardown { OpenLoam::Webhooks.reset_configuration! }

  def deliver(*answers, now: @now)
    transport = ScriptedTransport.new(*answers)
    OpenLoam::Webhooks.transport = transport
    with_tenant(@tenant) { OpenLoam::Webhooks.deliver(@delivery.reload, now: now) }
    @delivery.reload
    transport
  end

  test "a 2xx marks the delivery succeeded and the endpoint healthy" do
    transport = deliver(204)
    assert_equal "succeeded", @delivery.status
    assert_equal 1, @delivery.attempts
    assert_equal 204, @delivery.last_response_code
    assert_equal 7, @delivery.last_duration_ms
    assert_equal @now, @delivery.delivered_at
    assert_equal @now, @endpoint.reload.last_success_at
    assert_equal 1, transport.requests.size
  end

  test "the default body and the v1 signature are the frozen 0.3.0 shapes" do
    request = deliver(200).requests.first
    expected = OpenLoam::WebhookDeliveryJob.body_for("rental.equipment.created", { "id" => 7 }, @tenant.id)
    assert_equal expected, request[:body]
    assert_equal OpenLoam::WebhookDeliveryJob.signature(@endpoint.secret, expected), request[:headers]["X-OpenLoam-Signature"]
  end

  test "headers carry event, ids, timestamp and a verifiable v2 signature" do
    request = deliver(200).requests.first
    headers = request[:headers]
    body = request[:body]
    assert_equal "rental.equipment.created", headers["X-OpenLoam-Event"]
    assert_equal "evt-1", headers["X-OpenLoam-Event-Id"]
    assert_equal @delivery.delivery_id, headers["X-OpenLoam-Delivery"]
    assert_equal @now.to_i.to_s, headers["X-OpenLoam-Timestamp"]
    assert OpenLoam::Webhooks.verify_v2(headers["X-OpenLoam-Signature-V2"], body, @endpoint.secret, now: @now)
    refute OpenLoam::Webhooks.verify_v2(headers["X-OpenLoam-Signature-V2"], body, @endpoint.secret, now: @now + 301)
    refute OpenLoam::Webhooks.verify_v2(headers["X-OpenLoam-Signature-V2"], body + " ", @endpoint.secret, now: @now)
  end

  test "the v2 signature is pinned by a fixed vector and lists every signing secret" do
    assert_equal "t=1700000000,v1=8dbbbbf4523b10bbb793e74d854144c45acccc2d233667b1c06b805b6ded8a84",
                 OpenLoam::Webhooks.signature_v2([ "s3cr3t" ], '{"a":1}', 1_700_000_000)
    assert_equal "t=1700000000,v1=8dbbbbf4523b10bbb793e74d854144c45acccc2d233667b1c06b805b6ded8a84," \
                 "v1=5bed6ff4fdaa1f7539be4b82f6c76ce254e00e815b22b0dc8132056e0392cbcf",
                 OpenLoam::Webhooks.signature_v2(%w[s3cr3t old], '{"a":1}', 1_700_000_000)
  end

  test "the header prefix and user agent are configurable" do
    OpenLoam::Webhooks.header_prefix = "X-Acme"
    OpenLoam::Webhooks.user_agent = "Acme-Webhooks/1"
    headers = deliver(200).requests.first[:headers]
    assert headers.key?("X-Acme-Signature-V2")
    refute headers.key?("X-OpenLoam-Signature-V2")
    assert_equal "Acme-Webhooks/1", headers["User-Agent"]
  end

  test "a host body builder shapes the body per endpoint, and SkipDelivery cancels" do
    OpenLoam::Webhooks.body_builder = ->(endpoint:, delivery:) { { "type" => delivery.event_name, "url" => endpoint.url } }
    assert_equal({ "type" => "rental.equipment.created", "url" => "https://example.test/hook" },
                 JSON.parse(deliver(200).requests.first[:body]))

    with_tenant(@tenant) { @delivery.update!(status: "pending") }
    OpenLoam::Webhooks.body_builder = ->(**) { raise OpenLoam::Webhooks::SkipDelivery, "record erased" }
    transport = deliver(200)
    assert_equal "cancelled", @delivery.status
    assert_empty transport.requests
  end

  test "a host body builder error is retried without counting against the endpoint" do
    OpenLoam::Webhooks.body_builder = ->(**) { raise "host bug" }
    transport = deliver(200)
    assert_equal "pending", @delivery.status
    assert_not_nil @delivery.next_attempt_at
    assert_match(/host bug/, @delivery.last_error)
    assert_empty transport.requests
    assert_equal 0, @endpoint.reload.consecutive_failures
    assert_nil @endpoint.last_failure_at
  end

  test "a network error still counts against the endpoint" do
    deliver(Errno::ECONNREFUSED.new)
    assert_equal 1, @endpoint.reload.consecutive_failures
  end

  test "5xx, 408, 429 and network errors are retried on the schedule; Retry-After wins, capped at an hour" do
    deliver(503)
    assert_equal "pending", @delivery.status
    assert_in_delta 60, @delivery.next_attempt_at - @now, 6.1
    assert_equal "HTTP 503", @delivery.last_error

    second_try = @delivery.next_attempt_at
    deliver([ 429, "120" ], now: second_try)
    assert_equal 2, @delivery.attempts
    assert_equal second_try + 120, @delivery.next_attempt_at

    deliver(Errno::ECONNREFUSED.new, now: @delivery.next_attempt_at)
    assert_equal "pending", @delivery.status
    assert_match(/ECONNREFUSED/, @delivery.last_error)
  end

  test "after the last scheduled retry the delivery fails" do
    OpenLoam::Webhooks.retry_schedule = [ 60 ]
    deliver(500)
    deliver(500, now: @delivery.next_attempt_at)
    assert_equal "failed", @delivery.status
    assert_equal 2, @delivery.attempts
  end

  test "410 fails and disables the endpoint; other 4xx and 3xx fail without retry" do
    deliver(410)
    assert_equal "failed", @delivery.status
    refute @endpoint.reload.active?
    assert_equal "gone", @endpoint.disabled_reason

    with_tenant(@tenant) do
      @endpoint.enable!
      @delivery.update!(status: "pending", next_attempt_at: nil)
    end
    deliver(302)
    assert_equal "failed", @delivery.status
    assert_equal 1, @endpoint.reload.consecutive_failures
  end

  test "an inactive endpoint cancels the delivery without a request" do
    with_tenant(@tenant) { @endpoint.update!(active: false) }
    transport = deliver(200)
    assert_equal "cancelled", @delivery.status
    assert_empty transport.requests
  end

  test "a delivery that is not due, or already claimed, is not sent twice" do
    with_tenant(@tenant) { @delivery.update!(next_attempt_at: @now + 10) }
    assert_empty deliver(200).requests

    with_tenant(@tenant) { @delivery.update!(status: "succeeded") }
    assert_empty deliver(200).requests
  end

  test "a URL that now resolves inside the perimeter fails and disables the endpoint" do
    OpenLoam::Webhooks.transport = Class.new do
      def self.post(*, **) = raise(OpenLoam::OutboundUrl::BlockedError, "10.0.0.1 is not public")
    end
    with_tenant(@tenant) { OpenLoam::Webhooks.deliver(@delivery.reload, now: @now) }
    assert_equal "failed", @delivery.reload.status
    assert_equal "blocked_url", @endpoint.reload.disabled_reason
  end

  test "an unresolvable host is a retryable network error, not a disabled endpoint" do
    OpenLoam::Webhooks.transport = Class.new do
      def self.post(*, **) = raise(OpenLoam::OutboundUrl::UnresolvableError, "example.test does not resolve")
    end
    with_tenant(@tenant) { OpenLoam::Webhooks.deliver(@delivery.reload, now: @now) }
    @delivery.reload
    assert_equal "pending", @delivery.status
    assert_not_nil @delivery.next_attempt_at
    assert @endpoint.reload.active?
  end

  test "Retry-After is clamped to an hour" do
    deliver([ 503, "99999" ])
    assert_equal @now + 3600, @delivery.next_attempt_at
  end

  test "408 is retried" do
    deliver(408)
    assert_equal "pending", @delivery.status
    assert_equal "HTTP 408", @delivery.last_error
  end

  test "a bookkeeping error after the response propagates instead of becoming a retry" do
    original = OpenLoam::WebhookEndpoint.instance_method(:record_success!)
    OpenLoam::WebhookEndpoint.send(:define_method, :record_success!) { |*| raise "bookkeeping broke" }
    begin
      OpenLoam::Webhooks.transport = ScriptedTransport.new(200)
      error = assert_raises(RuntimeError) do
        with_tenant(@tenant) { OpenLoam::Webhooks.deliver(@delivery.reload, now: @now) }
      end
      assert_equal "bookkeeping broke", error.message
    ensure
      OpenLoam::WebhookEndpoint.send(:define_method, :record_success!, original)
    end
    assert_equal 0, @endpoint.reload.consecutive_failures
  end
end
