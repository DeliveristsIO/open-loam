module Loam
  # A thin domain event bus over ActiveSupport::Notifications.
  #
  # Convention: event names are `domain.thing.happened`, e.g.
  # "billing.subscription.renewed", "rental.equipment.created".
  # Publishing stamps the current tenant and actor onto the payload so
  # subscribers are always tenant-aware.
  module Events
    NAME_FORMAT = /\A[a-z0-9_]+(\.[a-z0-9_]+){2,}\z/
    PREFIX = "loam.event."

    def self.publish(name, payload = {})
      name = name.to_s
      unless name.match?(NAME_FORMAT)
        raise InvalidEventNameError, "Event name #{name.inspect} must follow `domain.thing.happened`"
      end

      ActiveSupport::Notifications.instrument(
        PREFIX + name,
        payload.merge(tenant_id: Loam::Current.tenant&.id, actor_id: Loam::Current.actor&.id)
      )
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
