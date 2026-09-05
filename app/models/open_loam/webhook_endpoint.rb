module OpenLoam
  # Where one tenant wants its domain events delivered. `event_pattern` uses
  # the same rule as OpenLoam::Events.subscribe — a trailing dot is a domain prefix
  # ("rental."), anything else is an exact event name.
  #
  # The secret signs every delivery (X-OpenLoam-Signature), so a receiver can tell
  # a real call from a forged one.
  class WebhookEndpoint < OpenLoam::TenantRecord
    self.table_name = "open_loam_webhook_endpoints"

    validates :url, presence: true
    validates :event_pattern, presence: true

    # The server fetches this URL, so a tenant must not be able to aim it at an
    # address only the server can reach. Rejected at save for a clear error;
    # OpenLoam::WebhookDeliveryJob re-checks at delivery, because DNS moves.
    validate :url_is_reachable_from_outside, if: -> { url.present? }

    scope :active, -> { where(active: true) }

    before_validation on: :create do
      self.secret ||= SecureRandom.hex(32)
    end

    # One matcher, shared with the event bus, so "rental." means the same thing
    # to a subscriber and to a webhook.
    def matches?(event_name)
      OpenLoam::Events.pattern_matches?(event_pattern, event_name)
    end

    private

    def url_is_reachable_from_outside
      OpenLoam::OutboundUrl.validate!(url)
    rescue OpenLoam::OutboundUrl::BlockedError => error
      errors.add(:url, error.message)
    end
  end
end
