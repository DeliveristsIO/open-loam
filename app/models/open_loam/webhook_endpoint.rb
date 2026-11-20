module OpenLoam
  # Where one tenant wants its domain events delivered. A pattern uses the rule
  # shared with OpenLoam::Events.subscribe: a trailing dot is a domain prefix
  # ("rental."), anything else is an exact event name. `event_pattern` is the
  # 0.3.0 single pattern; `event_patterns` holds several.
  #
  # The secret signs every delivery. With OpenLoam::Webhooks.encrypt_secrets on,
  # it is sealed with the tenant's key (OpenLoam::Encryption, "v2:..."); rows
  # written before that stay readable as plaintext.
  #
  # `metadata` belongs to the host app (e.g. which fields a receiver may see);
  # OpenLoam stores it and never reads it.
  class WebhookEndpoint < OpenLoam::TenantRecord
    self.table_name = "open_loam_webhook_endpoints"

    SEALED_PREFIXES = %w[v1: v2:].freeze

    has_many :deliveries, class_name: "OpenLoam::WebhookDelivery", foreign_key: :endpoint_id,
                          inverse_of: :endpoint, dependent: :delete_all

    validates :url, presence: true
    validate :at_least_one_pattern
    # The server fetches this URL, so a tenant must not aim it at an address only
    # the server can reach. Shape is checked at save; the delivery re-checks with
    # DNS, because DNS moves.
    validate :url_is_reachable_from_outside, if: -> { url.present? }

    scope :active, -> { where(active: true) }

    before_validation on: :create do
      self.secret = self.class.generate_secret if read_attribute(:secret).blank?
    end

    def self.generate_secret = SecureRandom.hex(32)

    def patterns
      list = Array(self[:event_patterns]).map(&:to_s).reject(&:empty?)
      list.empty? ? [ event_pattern.to_s ].reject(&:empty?) : list
    end

    def matches?(event_name)
      patterns.any? { |pattern| OpenLoam::Events.pattern_matches?(pattern, event_name) }
    end

    def settings
      value = self[:metadata]
      value = JSON.parse(value) if value.is_a?(String)
      (value || {}).to_h.stringify_keys
    end

    def secret = unseal(read_attribute(:secret), "secret")
    def secret=(value)
      write_attribute(:secret, seal(value, "secret"))
    end

    def previous_secret = unseal(read_attribute(:previous_secret), "previous_secret")
    def previous_secret=(value)
      write_attribute(:previous_secret, seal(value, "previous_secret"))
    end

    # The secrets a delivery is signed with right now: the current one, plus the
    # previous one while its grace period runs, so receivers can switch over.
    def signing_secrets(now = Time.current)
      keep_previous = previous_secret_expires_at && previous_secret_expires_at > now
      [ secret, (previous_secret if keep_previous) ].compact
    end

    def rotate_secret!(now: Time.current)
      new_secret = self.class.generate_secret
      update!(previous_secret: secret, previous_secret_expires_at: now + OpenLoam::Webhooks.secret_rotation_grace,
              secret: new_secret)
      new_secret
    end

    def record_success!(at = Time.current)
      update_columns(consecutive_failures: 0, failing_since: nil, last_success_at: at, updated_at: at)
    end

    # SQL increment, so two failing deliveries at once still count twice.
    # Disabled only when the streak is both long (disable_after_failures) and
    # old (failing_since at least disable_after_duration ago): a busy endpoint
    # can rack up many failures during a short outage and should survive it.
    def record_failure!(at = Time.current)
      self.class.where(id: id).update_all([ "consecutive_failures = consecutive_failures + 1, " \
                                            "failing_since = COALESCE(failing_since, ?), last_failure_at = ?, updated_at = ?",
                                            at, at, at ])
      reload
      disable!("consecutive_failures") if failing_long_enough?(at)
    end

    # Idempotent and race-safe: only the caller whose UPDATE flips the row from
    # on to off publishes the event.
    def disable!(reason)
      flipped = self.class.where(id: id, active: true)
                    .update_all(active: false, disabled_reason: reason.to_s, updated_at: Time.current) == 1
      return unless flipped

      reload
      OpenLoam::Events.publish(OpenLoam::Webhooks::DISABLED_EVENT, { endpoint_id: id, reason: reason.to_s })
    end

    def enable!
      update!(active: true, disabled_reason: nil, consecutive_failures: 0, failing_since: nil)
    end

    private

    def failing_long_enough?(at)
      limit = OpenLoam::Webhooks.disable_after_failures
      return false unless limit && consecutive_failures >= limit

      duration = OpenLoam::Webhooks.disable_after_duration
      duration.nil? || (failing_since && failing_since <= at - duration)
    end

    def at_least_one_pattern
      errors.add(:event_pattern, :blank) if patterns.empty?
    end

    def url_is_reachable_from_outside
      OpenLoam::OutboundUrl.validate!(url, require_https: OpenLoam::Webhooks.require_https?,
                                           ports: OpenLoam::Webhooks.allowed_ports)
    rescue OpenLoam::OutboundUrl::BlockedError => error
      errors.add(:url, error.message)
    end

    def key_scope = "tenant/#{tenant_id || OpenLoam.tenant!.id}"

    def seal(value, column)
      return value if value.nil? || !OpenLoam::Webhooks.encrypt_secrets?

      OpenLoam::Encryption.encrypt_scoped(value, key_scope,
                                          aad: OpenLoam::Encryption.aad(key_scope, self.class.table_name, column))
    end

    # A hex secret never contains ":", so anything without a version tag is a
    # plaintext row from before encryption was switched on.
    def unseal(stored, column)
      return stored if stored.nil? || SEALED_PREFIXES.none? { |prefix| stored.start_with?(prefix) }

      OpenLoam::Encryption.decrypt_scoped(stored, key_scope,
                                          aad: OpenLoam::Encryption.aad(key_scope, self.class.table_name, column))
    end
  end
end
