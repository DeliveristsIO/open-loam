module Loam
  # Durable (persistent) event subscribers — the twin of Loam::Events.subscribe,
  # and the formal contract L-706 pins down.
  #
  # THE CONTRACT
  #   * Ephemeral — Loam::Events.subscribe(&block): runs INLINE in the publisher's
  #     thread, synchronously, best-effort. An exception in the block PROPAGATES
  #     into whatever published the event. No persistence, no retry. Right for
  #     cheap in-process fan-out (the webhook dispatcher enqueues its own jobs
  #     this way).
  #   * Persistent — Loam::DurableEvents.register(...): publishing commits a
  #     Loam::EventDelivery row in the event's tenant, then hands the handler to a
  #     background job. The handler's exception is CONTAINED in the job; delivery
  #     is retried with backoff and, past MAX_ATTEMPTS, parked as `dead` for an
  #     operator (Admin::EventDeliveriesController).
  #
  # GUARANTEE: at-least-once, UNORDERED. Handlers MUST be idempotent — a retry or
  # the sweep may deliver the same event twice. Durability is of DELIVERY, not
  # CAPTURE: an event whose process dies between the after_commit and the publish
  # leaves no row and is lost, exactly as today. This feature makes what WAS
  # published arrive; it does not resurrect what was never published.
  #
  # SECURITY: a handler is resolved from THIS in-memory registry by key, populated
  # at boot from trusted code — never constantized from the stored row. If the key
  # is unknown at delivery time (handler removed since enqueue) the row is parked
  # `dead`; an arbitrary class is never executed off a DB value. (Same posture as
  # the scheduler's job_class allowlist.)
  module DurableEvents
    MAX_ATTEMPTS = 5
    # Backoff (seconds) indexed by attempt number; the last value is the cap.
    BACKOFF = [ 0, 60, 300, 1800, 7200 ].freeze
    SWEEP_KEY = "loam_event_redelivery_sweep".freeze

    class << self
      # --- declarative registry (mirrors Loam::Scheduler.register) ---

      # key:  a stable identifier stored on every delivery row it produces.
      # to:   an event name ("billing.invoice.paid") or a domain prefix
      #       ("billing.") — same matching rule as Events/webhooks.
      # call: a class (or anything) responding to .call(event_name, payload),
      #       or its name as a String. Resolved from this registry, never the row.
      def register(key:, to:, call:)
        registry[key.to_s] = { key: key.to_s, pattern: to.to_s, handler: call }
        key.to_s
      end

      def registered = registry.values

      def reset_registry!
        @registry = {}
      end

      def subscribers_for(event_name)
        registered.select { |entry| Loam::Events.pattern_matches?(entry[:pattern], event_name) }
      end

      def handler_for(key)
        entry = registry[key.to_s]
        entry && resolve(entry[:handler])
      end

      # --- wiring (mirrors Loam::Webhooks.subscribe!) ---

      # Wired once from Loam::Engine. Idempotent: subscribing twice would persist
      # every event twice.
      def subscribe!
        @subscription ||= Loam::Events.subscribe_all { |event_name, payload| capture(event_name, payload) }
      end

      # Persist a delivery row per matching durable subscriber, in the event's
      # tenant, then nudge a job per row. The ROW is the durable record; the job
      # is only the accelerator (the sweep redelivers rows whose job was lost).
      def capture(event_name, payload)
        tenant = Loam::Tenant.find_by(id: payload[:tenant_id])
        return if tenant.nil? # nil-tenant events are not durably delivered (as Webhooks.dispatch)

        matches = subscribers_for(event_name)
        return if matches.empty?

        # Only JSON-safe primitives cross into the row/job — payloads are ids and
        # scalars by convention, never records (same rule as the webhook path).
        deliverable = payload.transform_keys(&:to_s)

        Loam.as_tenant(tenant) do
          matches.each do |sub|
            delivery = Loam::EventDelivery.create!(
              subscriber_key: sub[:key], event_name: event_name.to_s,
              payload: deliverable, status: "pending", attempts: 0
            )
            Loam::EventDeliveryJob.perform_later(tenant.id, delivery.id)
          end
        end
      end

      # --- delivery (called by Loam::EventDeliveryJob) ---

      # Run one delivery and advance the row's state. Manual, ROW-STATE retries —
      # deliberately NOT ActiveJob retry_on, which keeps retry state in the queue
      # (the very thing this feature stops trusting). Safe to call twice on one
      # row (at-least-once): a delivered/dead/not-yet-due row is a no-op.
      def deliver(delivery, now: Time.current)
        return unless delivery.status == "pending"
        return if delivery.next_attempt_at && delivery.next_attempt_at > now # duplicate nudge, backoff not elapsed

        Loam::Telemetry.span("durable_event_delivery",
                             subscriber_key: delivery.subscriber_key, event_name: delivery.event_name) do
          run_delivery(delivery, now)
        end
      end

      def run_delivery(delivery, now)
        handler = handler_for(delivery.subscriber_key)
        if handler.nil?
          delivery.update!(status: "dead",
                           last_error: "no registered subscriber #{delivery.subscriber_key.inspect}")
          return
        end

        begin
          handler.call(delivery.event_name, delivery.payload_hash)
          delivery.update!(status: "delivered", delivered_at: now, last_error: nil)
        rescue StandardError => error
          attempts = delivery.attempts + 1
          if attempts >= MAX_ATTEMPTS
            delivery.update!(status: "dead", attempts: attempts, last_error: format_error(error))
          else
            delivery.update!(attempts: attempts, next_attempt_at: now + backoff_for(attempts),
                             last_error: format_error(error))
          end
        end
      end

      # THE durability guarantee: re-enqueue due-but-undelivered rows whose job
      # was lost (worker crash, dropped message, async adapter racing the txn).
      # Tenant-scoped — called from the per-tenant sweep the engine registers, so
      # no cross-tenant scan is needed.
      def redeliver_stuck(now: Time.current, limit: 500)
        count = 0
        Loam::EventDelivery.due(now).limit(limit).find_each do |delivery|
          Loam::EventDeliveryJob.perform_later(delivery.tenant_id, delivery.id)
          count += 1
        end
        count
      end

      private

      def registry
        @registry ||= {}
      end

      # A callable passed directly (class with .call, Proc) is used as-is; a
      # String/Symbol is constantized HERE, from the trusted registry value.
      def resolve(handler)
        if handler.is_a?(String) || handler.is_a?(Symbol)
          klass = handler.to_s.safe_constantize
          return klass if klass.respond_to?(:call)

          nil
        elsif handler.respond_to?(:call)
          handler
        end
      end

      def backoff_for(attempts)
        BACKOFF[attempts] || BACKOFF.last
      end

      def format_error(error)
        "#{error.class}: #{error.message}"
      end
    end
  end
end
