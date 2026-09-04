module OpenLoam
  # One received inbound webhook. Two jobs: an idempotency ledger (a unique
  # (source_id, external_id) index turns a replayed delivery into a no-op) and an
  # audit/payload store — the raw body is kept here so an event subscriber reads
  # it, keeping the published event payload scalar-clean (ids only).
  class InboundWebhookDelivery < OpenLoam::TenantRecord
    self.table_name = "open_loam_inbound_webhook_deliveries"

    belongs_to :source, class_name: "OpenLoam::InboundWebhookSource", inverse_of: :deliveries

    validates :external_id, presence: true
    # (source_id, external_id) uniqueness is enforced by a DB index — the ledger
    # must be race-safe, so we rely on the constraint, not a validation.

    def payload_hash
      value = self[:payload]
      return value if value.is_a?(Hash)

      JSON.parse(value.to_s.presence || "{}")
    rescue JSON::ParserError
      {}
    end
  end
end
