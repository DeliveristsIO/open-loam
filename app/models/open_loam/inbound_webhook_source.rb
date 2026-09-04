module Loam
  # A registered external system allowed to POST webhooks INTO this tenant — the
  # inbound sibling of Loam::WebhookEndpoint (which delivers events OUT). The
  # `token` is the unguessable URL id (`/webhooks/:token`) that identifies the
  # source; the `secret` is the HMAC key that AUTHENTICATES each call. Identity is
  # not authority: rotating either is supported from the admin.
  #
  # On a verified delivery, Loam publishes `event_name` onto the domain event bus
  # with a reference to the stored Loam::InboundWebhookDelivery, so durable
  # subscribers (Loam::DurableEvents) react — the payload itself lives on the row.
  class InboundWebhookSource < Loam::TenantRecord
    self.table_name = "loam_inbound_webhook_sources"

    DEFAULT_SIGNATURE_HEADER = "X-Loam-Signature".freeze
    DEFAULT_TOLERANCE = 300 # seconds

    has_many :deliveries, class_name: "Loam::InboundWebhookDelivery",
                          foreign_key: :source_id, dependent: :destroy, inverse_of: :source

    validates :name, presence: true
    validates :token, presence: true, uniqueness: true
    validates :secret, presence: true
    validates :event_name, presence: true,
              format: { with: Loam::Events::NAME_FORMAT, message: "must follow domain.thing.happened" }

    scope :active, -> { where(active: true) }

    before_validation on: :create do
      self.token ||= SecureRandom.hex(24)
      self.secret ||= SecureRandom.hex(32)
      self.signature_header = DEFAULT_SIGNATURE_HEADER if signature_header.blank?
      self.active = true if active.nil?
    end

    # THE blessed cross-tenant lookup (see Loam::ApiToken.authenticate): a public
    # inbound request arrives with no tenant context — the token in the URL is how
    # it discovers its tenant. Establishes Loam::Current.tenant (never an actor:
    # the sender is a machine, not a user) and returns the ACTIVE source, or nil.
    def self.resolve(raw_token)
      return nil if raw_token.blank?

      source = unscoped.find_by(token: raw_token)
      return nil unless source&.active?

      Loam::Current.tenant = source.tenant
      source
    end

    def signature_header_key = signature_header.presence || DEFAULT_SIGNATURE_HEADER
    def tolerance = (timestamp_tolerance.presence || DEFAULT_TOLERANCE).to_i

    def rotate_token!  = update!(token: SecureRandom.hex(24))
    def rotate_secret! = update!(secret: SecureRandom.hex(32))
  end
end
