require "json"
require "openssl"
require "securerandom"

module OpenLoam
  # Domain events, delivered over HTTP to whoever asked for them.
  #
  # One global subscriber listens to every OpenLoam event and, in the tenant the
  # event was published in, enqueues a delivery per matching active endpoint.
  # Matching happens at dispatch time rather than at subscribe time because
  # endpoints are data: a tenant can add one from the admin without a reboot.
  module Webhooks
    DEFAULT_RETRY_SCHEDULE = [ 60, 300, 1_800, 7_200, 21_600, 43_200, 86_400 ].freeze
    DISABLED_EVENT = "open_loam.webhook.endpoint_disabled".freeze
    TEST_EVENT = "open_loam.webhook.test".freeze
    EXCERPT_BYTES = 512
    TIMESTAMP_TOLERANCE = 300

    CONFIG_IVARS = %i[
      @header_prefix @user_agent @retry_schedule @disable_after_failures @delivery_retention @body_builder
      @transport @require_https @allowed_ports @encrypt_secrets @test_event_name @timeout
      @secret_rotation_grace @stuck_after
    ].freeze

    Response = Struct.new(:code, :headers, :excerpt, :duration_ms, keyword_init: true)

    # Raised by a host body builder to drop one delivery on purpose (the record
    # it describes is gone, the receiver may not see this event). The row is
    # cancelled, not failed, and the endpoint's health is untouched.
    class SkipDelivery < OpenLoam::Error; end

    RETRYABLE_CODES = [ 408, 429 ].freeze
    MAX_RETRY_AFTER = 3_600

    class << self
      attr_writer :header_prefix, :user_agent, :retry_schedule, :disable_after_failures, :delivery_retention,
                  :body_builder, :transport, :require_https, :allowed_ports, :encrypt_secrets, :test_event_name,
                  :timeout, :secret_rotation_grace, :stuck_after

      def header_prefix = @header_prefix || "X-OpenLoam"
      def user_agent = @user_agent || "OpenLoam-Webhooks/#{OpenLoam::VERSION}"
      def retry_schedule = @retry_schedule || DEFAULT_RETRY_SCHEDULE
      def disable_after_failures = defined?(@disable_after_failures) ? @disable_after_failures : 50
      def delivery_retention = defined?(@delivery_retention) ? @delivery_retention : 30.days
      def body_builder = @body_builder
      def transport = @transport || HttpTransport
      def require_https? = @require_https ? true : false
      def allowed_ports = @allowed_ports
      def encrypt_secrets? = @encrypt_secrets ? true : false
      def test_event_name = @test_event_name || TEST_EVENT
      def timeout = @timeout || 10
      def secret_rotation_grace = @secret_rotation_grace || 24.hours
      def stuck_after = @stuck_after || 5.minutes

      # Tests (and only tests) put the module back to its defaults.
      def reset_configuration!
        CONFIG_IVARS.each { |ivar| remove_instance_variable(ivar) if instance_variable_defined?(ivar) }
      end

      # One attempt for one row, inside the row's tenant. Safe to call twice:
      # only the caller that flips pending -> sending sends.
      def deliver(delivery, now: Time.current)
        return unless claim(delivery, now)

        delivery.reload
        endpoint = delivery.endpoint
        unless endpoint&.active?
          delivery.update!(status: "cancelled", sending_at: nil, last_error: "endpoint inactive")
          return
        end

        begin
          body = body_for(endpoint, delivery)
          response = transport.post(endpoint.url, body: body, headers: headers_for(endpoint, delivery, body, now), timeout: timeout)
        rescue SkipDelivery => error
          delivery.update!(status: "cancelled", sending_at: nil, last_error: short(error.message))
          return
        rescue OpenLoam::OutboundUrl::UnresolvableError => error
          # DNS being down is the network's fault, not the receiver's: retry.
          retry_later(delivery, endpoint, now, error: short("#{error.class}: #{error.message}"))
          return
        rescue OpenLoam::OutboundUrl::BlockedError => error
          delivery.update!(status: "failed", sending_at: nil, last_error: short("blocked: #{error.message}"))
          endpoint.disable!("blocked_url")
          return
        rescue StandardError => error
          retry_later(delivery, endpoint, now, error: short("#{error.class}: #{error.message}"))
          return
        end

        # Outside the rescue: a bookkeeping error must surface, not become a retry.
        record_response(delivery, endpoint, response, now)
      end

      def body_for(endpoint, delivery)
        if body_builder
          JSON.generate(body_builder.call(endpoint: endpoint, delivery: delivery))
        else
          OpenLoam::WebhookDeliveryJob.body_for(delivery.event_name, delivery.payload_hash, delivery.tenant_id)
        end
      end

      def headers_for(endpoint, delivery, body, now)
        timestamp = now.to_i
        prefix = header_prefix
        {
          "Content-Type" => "application/json",
          "User-Agent" => user_agent,
          "#{prefix}-Event" => delivery.event_name,
          "#{prefix}-Event-Id" => delivery.event_id,
          "#{prefix}-Delivery" => delivery.delivery_id,
          "#{prefix}-Timestamp" => timestamp.to_s,
          "#{prefix}-Signature" => OpenLoam::WebhookDeliveryJob.signature(endpoint.secret, body),
          "#{prefix}-Signature-V2" => signature_v2(endpoint.signing_secrets(now), body, timestamp)
        }
      end

      # "t=<unix>,v1=<hex>[,v1=<hex>]" — HMAC-SHA256 of "<t>.<body>" under each
      # signing secret. The timestamp is inside the MAC, so a captured request
      # cannot be replayed after the receiver's tolerance window.
      def signature_v2(secrets, body, timestamp)
        macs = Array(secrets).map { |secret| "v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret.to_s, "#{timestamp}.#{body}")}" }
        ([ "t=#{timestamp}" ] + macs).join(",")
      end

      # Reference verifier (docs and tests): constant-time compare, bounded clock skew.
      def verify_v2(header, body, secret, now: Time.current, tolerance: TIMESTAMP_TOLERANCE)
        parts = header.to_s.split(",").map { |part| part.split("=", 2) }
        timestamp = parts.find { |key, _| key == "t" }&.last.to_i
        return false if timestamp.zero? || (now.to_i - timestamp).abs > tolerance

        expected = OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, "#{timestamp}.#{body}")
        parts.any? { |key, value| key == "v1" && value && ActiveSupport::SecurityUtils.secure_compare(value, expected) }
      end

      # Runs inline in whatever published the event, inside its transaction when
      # there is one: the ledger rows commit or roll back with the change itself,
      # and the jobs are enqueued only after that commit.
      def dispatch(event_name, payload)
        tenant = OpenLoam::Tenant.find_by(id: payload[:tenant_id])
        return if tenant.nil?

        deliverable = payload.transform_keys(&:to_s)
        event_id = SecureRandom.uuid

        OpenLoam.as_tenant(tenant) do
          OpenLoam::WebhookEndpoint.active.each do |endpoint|
            next unless endpoint.matches?(event_name)

            enqueue(endpoint.deliveries.create!(event_id: event_id, event_name: event_name.to_s, payload: deliverable))
          end
        end
      end

      def send_test!(endpoint)
        delivery = endpoint.deliveries.create!(event_id: SecureRandom.uuid, event_name: test_event_name,
                                               payload: { "test" => true, "tenant_id" => endpoint.tenant_id })
        enqueue(delivery)
        delivery
      end

      # Manual redelivery of a finished row: restarts the full retry schedule
      # (attempts reset). Non-final (pending/sending) rows are returned untouched.
      def redeliver!(delivery)
        return delivery unless delivery.final?

        delivery.update!(status: "pending", attempts: 0, next_attempt_at: nil, sending_at: nil)
        enqueue(delivery)
        delivery
      end

      def enqueue(delivery)
        tenant_id = delivery.tenant_id
        delivery_id = delivery.id
        after_commit { OpenLoam::WebhookDeliveryJob.perform_later(tenant_id, delivery_id) }
      end

      # Rails >= 7.2 defers to the outermost commit (and runs at once when no
      # transaction is open). On 7.1 the job may start before the row is visible;
      # it then finds nothing and the sweep picks the row up.
      def after_commit(&block)
        if ActiveRecord.respond_to?(:after_all_transactions_commit)
          ActiveRecord.after_all_transactions_commit(&block)
        else
          block.call
        end
      end

      private

      def claim(delivery, now)
        OpenLoam::WebhookDelivery.where(id: delivery.id, status: "pending")
                                 .where("next_attempt_at IS NULL OR next_attempt_at <= ?", now)
                                 .update_all([ "status = 'sending', sending_at = ?, attempts = attempts + 1, updated_at = ?", now, now ]) == 1
      end

      def record_response(delivery, endpoint, response, now)
        attrs = { last_response_code: response.code, last_duration_ms: response.duration_ms,
                  response_excerpt: response.excerpt, sending_at: nil }
        case response.code
        when 200..299
          delivery.update!(attrs.merge(status: "succeeded", delivered_at: now, last_error: nil, next_attempt_at: nil))
          endpoint.record_success!(now)
        when 410
          delivery.update!(attrs.merge(status: "failed", last_error: "HTTP 410"))
          endpoint.disable!("gone")
        when *RETRYABLE_CODES, 500..599
          delivery.assign_attributes(attrs)
          retry_later(delivery, endpoint, now, error: "HTTP #{response.code}", retry_after: retry_after_seconds(response))
        else
          delivery.update!(attrs.merge(status: "failed", last_error: "HTTP #{response.code}"))
          endpoint.record_failure!(now)
        end
      end

      def retry_later(delivery, endpoint, now, error:, retry_after: nil)
        endpoint&.record_failure!(now)
        delay = retry_schedule[delivery.attempts - 1]
        if delay.nil?
          delivery.update!(status: "failed", sending_at: nil, last_error: error)
          return
        end

        wait = retry_after || (delay * (0.9 + (rand * 0.2))).round
        delivery.update!(status: "pending", sending_at: nil, last_error: error, next_attempt_at: now + wait)
        OpenLoam::WebhookDeliveryJob.set(wait: wait).perform_later(delivery.tenant_id, delivery.id)
      end

      def retry_after_seconds(response)
        value = response.headers.to_h["retry-after"].to_s
        return nil unless value.match?(/\A\d+\z/)

        value.to_i.clamp(1, MAX_RETRY_AFTER)
      end

      def short(message) = message.to_s.truncate(255)
    end

    # Wired once from OpenLoam::Engine. Idempotent: subscribing twice would deliver
    # every event twice.
    def self.subscribe!
      @subscription ||= Events.subscribe_all { |event_name, payload| dispatch(event_name, payload) }
    end
  end
end
