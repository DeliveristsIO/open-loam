module Loam
  # The real-time bridge: pushes selected Loam events to a browser over
  # Server-Sent Events, so the admin updates live instead of polling.
  #
  # SECURITY POSTURE — default OFF. An event reaches a browser only if ALL hold:
  #   * its name matches a declared Loam.broadcast_events pattern (opt-in), AND
  #   * its tenant matches the connected tenant (isolation), AND
  #   * its audience includes the connected actor (a payload `user_id`, if any,
  #     is the sole recipient; no `user_id` means tenant-wide).
  #
  # FAN-OUT is behind a swappable broadcaster seam (Loam::EventStream.broadcaster).
  # The default in-process broadcaster only sees events published in THIS process
  # — fine for the single-process prototype; a multi-process deploy swaps in a
  # Redis/SolidCable-backed broadcaster with no controller change (see
  # docs/architecture.md).
  module EventStream
    class << self
      attr_writer :broadcaster

      def broadcaster
        @broadcaster ||= InProcessBroadcaster.new
      end

      # Is this event name allowed to reach browsers at all? Empty allow-list →
      # false, always (nothing leaks by default).
      def broadcastable?(event_name)
        Loam.broadcast_events.any? do |pattern|
          next false if Loam::Overrides.disabled?(:broadcast_events, pattern) # an app can turn a default pattern off

          Loam::Events.pattern_matches?(pattern, event_name)
        end
      end

      # Should a broadcastable event reach a stream connected as (tenant, actor)?
      def deliverable?(event_name, payload, tenant:, actor:)
        return false unless broadcastable?(event_name)

        payload = payload.symbolize_keys
        return false unless payload[:tenant_id] == tenant&.id

        recipient = payload[:user_id]
        recipient.nil? || recipient == actor&.id
      end

      # One SSE message: an `event:` line (the Loam event name) and a `data:`
      # line (JSON), ended by a blank line. Only small id-ish keys ride along —
      # Loam events carry no attribute values, and this slices to a safe set as
      # belt-and-suspenders (tenant_id is dropped; it is implied by the connection).
      def frame(event_name, payload)
        "event: #{event_name}\ndata: #{safe_payload(payload).to_json}\n\n"
      end

      private

      def safe_payload(payload)
        # id-ish keys only — never attribute values. percent/status ride along for
        # the progress bar (Loam::ProgressJob); both are non-sensitive.
        payload.symbolize_keys.slice(:id, :type, :user_id, :from, :to, :percent, :status).compact
      end
    end

    # The default fan-out: subscribe to Loam::Events in THIS process and forward
    # the events deliverable to (tenant, actor) to a sink. A `sink` is anything
    # answering #call(sse_string) — the controller's is a Queue push.
    class InProcessBroadcaster
      # Returns an opaque handle to pass back to #unsubscribe.
      def subscribe(tenant:, actor:, &sink)
        Loam::Events.subscribe_all do |event_name, payload|
          next unless Loam::EventStream.deliverable?(event_name, payload, tenant: tenant, actor: actor)

          sink.call(Loam::EventStream.frame(event_name, payload))
        end
      end

      def unsubscribe(handle)
        ActiveSupport::Notifications.unsubscribe(handle) if handle
      end
    end
  end
end
