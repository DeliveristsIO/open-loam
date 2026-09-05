module OpenLoam
  # The event LOG — every published event, captured as a queryable row.
  #
  # WHY THIS EXISTS. OpenLoam::Events is ActiveSupport::Notifications: a publish
  # reaches whoever is subscribed at that instant and is then gone. OpenLoam::DurableEvents
  # made *delivery* durable (a row per registered subscriber, retried until it
  # lands) but says so itself: "Durability is of DELIVERY, not CAPTURE". Nothing
  # recorded the event itself, so "what happened in this tenant last Tuesday" had
  # no answer and a stream could not be replayed. This module is the capture half.
  #
  # CAPTURE IS ON BY DEFAULT, and deliberately so. The comparable default-OFF
  # switch is OpenLoam.broadcast_events, which governs EXPOSURE — events crossing
  # out to a browser, where a stray event is a leak. This is the other kind: an
  # internal, tenant-scoped record, the same posture as audit-by-default in
  # OpenLoam::Auditable. An opt-in log is a log nobody turns on.
  #
  # WHAT LANDS IN THE ROW is the published payload, which by OpenLoam convention
  # carries ids and scalars — never records (the same rule the webhook and durable
  # paths already rely on). Anything a publisher puts in a payload is written
  # here, so a payload is an authored, reviewable choice at each call site; that
  # is what makes capture-all safe where blanket model-state serialization would
  # not be. Exclude a chatty or sensitive stream with OpenLoam.uncaptured_events.
  #
  # FAILURE POSTURE: capture runs INLINE in the publisher's thread (it is an
  # ephemeral OpenLoam::Events subscriber), so a failed insert PROPAGATES into
  # whatever published the event. That is the intended trade: a log that silently
  # drops entries is not a log, and the alternative — swallowing the error — makes
  # the gap this feature exists to close invisible again.
  module EventLog
    PRUNE_KEY = "open_loam_event_log_prune".freeze

    class << self
      # Wired once from OpenLoam::Engine. Idempotent: subscribing twice would
      # capture every event twice.
      def subscribe!
        @subscription ||= OpenLoam::Events.subscribe_all { |event_name, payload| capture(event_name, payload) }
      end

      # Capture-all is the ABSENCE of configuration, not an allow-list entry:
      # OpenLoam::Events.pattern_matches? has no match-all spelling ("" is an exact
      # match against the empty name, which never matches). So the only knob is
      # the exclusion list, and an empty one captures everything.
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

      # --- reading ---

      # Every captured event in the current tenant matching one event name
      # ("rental.equipment.created") or a domain prefix ("rental."), oldest
      # first — the shape a replay wants. Same matching rule as subscribe.
      def read(name_or_prefix = nil, since: nil, limit: nil)
        scope = OpenLoam::EventRecord.chronological
        scope = scope.matching(name_or_prefix) if name_or_prefix.present?
        scope = scope.where(occurred_at: since..) if since
        scope = scope.limit(limit) if limit
        scope
      end

      # Re-run a captured stream through a handler. The handler sees exactly what
      # a subscriber saw live — (event_name, payload) — and MUST be idempotent:
      # replay is a re-read of history, not a second publish, so nothing else on
      # the bus fires and a replayed event is not re-captured.
      def replay(name_or_prefix = nil, since: nil, limit: nil, &handler)
        read(name_or_prefix, since: since, limit: limit).each do |record|
          handler.call(record.name, record.payload_hash)
        end
      end

      # --- retention ---

      # Capture-all grows without bound, so the log has a retention window and a
      # per-tenant sweep that enforces it (OpenLoam::EventLogPruneJob).
      #
      # delete_all, NOT destroy_all: OpenLoam::EventRecord is readonly once
      # persisted (the log is append-only), and destroy on a readonly record
      # raises ActiveRecord::ReadOnlyRecord. delete_all issues one DELETE and
      # never instantiates a row.
      def prune(now: Time.current)
        retention = OpenLoam.event_log_retention
        return 0 if retention.nil?

        OpenLoam::EventRecord.where(occurred_at: ...(now - retention)).delete_all
      end
    end
  end
end
