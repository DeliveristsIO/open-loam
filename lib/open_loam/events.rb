module OpenLoam
  # A thin domain event bus over ActiveSupport::Notifications.
  #
  # Convention: event names are `domain.thing.happened`, e.g.
  # "billing.subscription.renewed", "rental.equipment.created".
  # Publishing stamps the current tenant and actor onto the payload so
  # subscribers are always tenant-aware.
  module Events
    NAME_FORMAT = /\A[a-z0-9_]+(\.[a-z0-9_]+){2,}\z/
    PREFIX = "open_loam.event."

    def self.publish(name, payload = {})
      name = name.to_s
      unless name.match?(NAME_FORMAT)
        raise InvalidEventNameError, "Event name #{name.inspect} must follow `domain.thing.happened`"
      end

      ActiveSupport::Notifications.instrument(
        PREFIX + name,
        payload.merge(tenant_id: OpenLoam::Current.tenant&.id, actor_id: OpenLoam::Current.actor&.id)
      )
    end

    # The subscription rule, in one place: a trailing dot is a domain prefix,
    # anything else is an exact event name. OpenLoam::WebhookEndpoint matches
    # against this too, so a pattern means the same thing everywhere.
    def self.pattern_matches?(pattern, event_name)
      pattern = pattern.to_s
      event_name = event_name.to_s

      pattern.end_with?(".") ? event_name.start_with?(pattern) : event_name == pattern
    end

    # Every OpenLoam event, whatever its domain — the empty prefix matches them
    # all. Used by the webhook dispatcher, which decides per event which
    # endpoints care.
    def self.subscribe_all(&block)
      subscribe("", &block)
    end

    # Subscribe to one event ("rental.equipment.created") or a whole domain
    # ("rental.") — the block receives (event_name, payload).
    def self.subscribe(name_or_prefix, &block)
      pattern = PREFIX + name_or_prefix.to_s
      matcher = pattern.end_with?(".") ? /\A#{Regexp.escape(pattern)}/ : pattern
      ActiveSupport::Notifications.subscribe(matcher) do |full_name, _start, _finish, _id, payload|
        block.call(full_name.delete_prefix(PREFIX), payload)
      end
    end
  end
end
