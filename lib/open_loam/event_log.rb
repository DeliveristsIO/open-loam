module OpenLoam
  # Captures every published event as a queryable OpenLoam::EventRecord row —
  # the capture half of the event system, where OpenLoam::DurableEvents is the
  # delivery half ("durability is of DELIVERY, not CAPTURE").
  #
  # Capture is ON by default and captures everything but OpenLoam.uncaptured_events.
  # That inverts OpenLoam.broadcast_events on purpose; see ADR 0007 for why, and
  # for why this stayed in-gem rather than adopting Rails Event Store.
  #
  # Capture runs INLINE in the publisher's thread, so a failed insert propagates
  # into whatever published the event. Deliberate — do not rescue it. Swallowing
  # the error re-opens the silent gap this module exists to close.
  module EventLog
    PRUNE_KEY = "open_loam_event_log_prune".freeze

    class << self
      # Idempotent: subscribing twice would capture every event twice.
      def subscribe!
        @subscription ||= OpenLoam::Events.subscribe_all { |event_name, payload| capture(event_name, payload) }
      end

      # Exclusion is the only knob, because pattern_matches? has no match-all
      # spelling ("" is an exact match on the empty name). Do not add an
      # allow-list: capture-all has to stay the absence of configuration.
      def capturable?(event_name)
        OpenLoam.uncaptured_events.none? do |pattern|
          next false if OpenLoam::Overrides.disabled?(:uncaptured_events, pattern) # an app can re-enable a default exclusion

          OpenLoam::Events.pattern_matches?(pattern, event_name)
        end
      end

      def capture(event_name, payload)
        return unless capturable?(event_name)

        tenant = OpenLoam::Tenant.find_by(id: payload[:tenant_id])
        return if tenant.nil? # nil-tenant events are not captured (as Webhooks.dispatch / DurableEvents.capture)

        OpenLoam.as_tenant(tenant) do
          OpenLoam::EventRecord.create!(
            name: event_name.to_s,
            payload: payload.transform_keys(&:to_s),
            occurred_at: Time.current
          )
        end
      end

      # name_or_prefix takes an exact event name or a trailing-dot domain
      # prefix, the same rule as Events.subscribe. Oldest first.
      def read(name_or_prefix = nil, since: nil, limit: nil)
        scope = OpenLoam::EventRecord.chronological
        scope = scope.matching(name_or_prefix) if name_or_prefix.present?
        scope = scope.where(occurred_at: since..) if since
        scope = scope.limit(limit) if limit
        scope
      end

      # A re-read of history, NOT a second publish: nothing else on the bus fires
      # and a replayed event is not re-captured. Handlers must be idempotent, and
      # get string payload keys (from the row) where a live subscriber got symbols.
      def replay(name_or_prefix = nil, since: nil, limit: nil, &handler)
        read(name_or_prefix, since: since, limit: limit).each do |record|
          handler.call(record.name, record.payload_hash)
        end
      end

      # delete_all, NOT destroy_all: rows are readonly once persisted, and
      # destroy on a readonly record raises ActiveRecord::ReadOnlyRecord.
      def prune(now: Time.current)
        retention = OpenLoam.event_log_retention
        return 0 if retention.nil?

        OpenLoam::EventRecord.where(occurred_at: ...(now - retention)).delete_all
      end
    end
  end
end
