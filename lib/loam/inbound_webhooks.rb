require "openssl"
require "digest"

module Loam
  # Receiving webhooks FROM external systems (the inbound sibling of
  # Loam::Webhooks). One entry point — `ingest` — does the whole verified,
  # replay-resistant pipeline and returns a Result the controller turns into an
  # HTTP status. Kept here (not in a controller) so it is testable without HTTP
  # and shared by the generated app and the demo.
  #
  # THE ORDER OF CHECKS is deliberate — cheapest and least-trusting first:
  #   1. body size      -> 413  (never HMAC a huge body)
  #   2. token resolve  -> 404  (unknown/inactive source)
  #   3. signature      -> 401  (constant-time HMAC over the RAW body)
  #   4. timestamp      -> 401  (defense-in-depth; see note below)
  #   5. dedupe         -> 200  (a replay is idempotent, not an error)
  #   6. ingest+publish -> 202
  #
  # Every AUTH failure returns 401 with no distinguishing body, so a sender can't
  # probe which check failed; the specific reason is logged server-side only.
  #
  # REPLAY: the real defense is the (source_id, external_id) dedupe. The timestamp
  # window is defense-in-depth: unless the sender signs the timestamp too, a
  # replayer can refresh an unsigned timestamp header. Don't over-trust it.
  module InboundWebhooks
    MAX_BYTES = 1_000_000

    Result = Struct.new(:status, :reason, :delivery, keyword_init: true)

    module_function

    def ingest(token:, raw_body:, headers:)
      Loam::Telemetry.span("inbound_webhook") { run_ingest(token, raw_body.to_s, headers) }
    end

    def run_ingest(token, raw_body, headers)
      return Result.new(status: 413, reason: "body too large") if raw_body.bytesize > MAX_BYTES

      source = Loam::InboundWebhookSource.resolve(token)
      return Result.new(status: 404, reason: "unknown or inactive source") if source.nil?

      signature = header(headers, source.signature_header_key)
      return unauthorized("missing signature") if signature.blank?
      return unauthorized("bad signature") unless valid_signature?(source.secret, raw_body, signature)

      if source.timestamp_header.present?
        return unauthorized("stale or missing timestamp") unless fresh_timestamp?(header(headers, source.timestamp_header), source.tolerance)
      end

      external_id = delivery_id(source, headers, raw_body)

      begin
        delivery = nil
        Loam::InboundWebhookDelivery.transaction do
          delivery = Loam::InboundWebhookDelivery.create!(
            source: source, external_id: external_id, event_name: source.event_name,
            status: "received", received_at: Time.current, payload: parse(raw_body)
          )
          # Scalar-only payload by convention (like the outbound path): the body
          # lives on the delivery row, subscribers read it from there. Publishing
          # inside the txn ties capture to the row — a publish failure rolls the
          # row back so the sender's retry isn't deduped away.
          Loam::Events.publish(source.event_name, { source_id: source.id, delivery_id: delivery.id })
        end
        Result.new(status: 202, reason: "accepted", delivery: delivery)
      rescue ActiveRecord::RecordNotUnique
        # A concurrent or replayed delivery with the same external_id — already
        # processed. Idempotent success, NOT a second publish.
        Result.new(status: 200, reason: "duplicate (already processed)")
      end
    end

    # --- verification internals ---

    def valid_signature?(secret, body, provided)
      expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, body)
      # Hash both to a fixed 64-hex length so the compare is constant-time and
      # never raises on an attacker-chosen length.
      ActiveSupport::SecurityUtils.fixed_length_secure_compare(
        Digest::SHA256.hexdigest(expected), Digest::SHA256.hexdigest(provided.to_s)
      )
    rescue StandardError
      false
    end

    def fresh_timestamp?(raw, tolerance)
      return false if raw.blank?

      seconds = (Integer(raw.to_s) rescue (Time.parse(raw.to_s).to_i rescue nil))
      return false if seconds.nil?

      (Time.current.to_i - seconds).abs <= tolerance.to_i
    end

    def delivery_id(source, headers, body)
      if source.delivery_id_header.present?
        value = header(headers, source.delivery_id_header)
        return value if value.present?
      end
      # No delivery-id header configured (or absent): fall back to a body hash.
      # Consequence: identical bodies dedupe. A sender with a real delivery id
      # should configure delivery_id_header so distinct-but-identical bodies pass.
      Digest::SHA256.hexdigest(body)
    end

    def header(headers, name)
      return nil if name.blank?

      # ActionDispatch::Http::Headers is case-insensitive on []; a plain Hash
      # (tests) is not — try the given key then a couple of common casings.
      headers[name] || headers[name.to_s] || headers[name.to_s.downcase] ||
        headers["HTTP_#{name.to_s.upcase.tr('-', '_')}"]
    end

    def parse(raw_body)
      JSON.parse(raw_body)
    rescue JSON::ParserError
      { "raw" => raw_body }
    end

    def unauthorized(reason)
      Result.new(status: 401, reason: reason)
    end
  end
end
