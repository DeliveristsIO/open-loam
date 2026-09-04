module OpenLoam
  # One durable delivery of one event to one persistent subscriber
  # (see OpenLoam::DurableEvents). The ROW is the durable record of intent: it is
  # committed in the event's tenant at publish time, and the background job is
  # only an accelerator. If the job is lost, the sweep re-enqueues from this row.
  #
  # Lifecycle: pending -> delivered (handler ran) | dead (handler removed, or
  # MAX_ATTEMPTS exhausted). A pending row with next_attempt_at in the future is
  # simply waiting out its backoff.
  class EventDelivery < OpenLoam::TenantRecord
    self.table_name = "open_loam_event_deliveries"

    STATUSES = %w[pending delivered dead].freeze

    validates :subscriber_key, :event_name, presence: true
    validates :status, inclusion: { in: STATUSES }

    scope :pending,   -> { where(status: "pending") }
    scope :delivered, -> { where(status: "delivered") }
    scope :dead,      -> { where(status: "dead") }

    # Rows ready for a (re)delivery attempt: pending and past their backoff gate.
    scope :due, ->(now = Time.current) {
      pending.where("next_attempt_at IS NULL OR next_attempt_at <= ?", now)
    }

    # The stored payload as a Hash regardless of adapter (Postgres jsonb returns
    # a Hash; a text/json column may hand back a String).
    def payload_hash
      value = self[:payload]
      return value if value.is_a?(Hash)

      JSON.parse(value.to_s.presence || "{}")
    rescue JSON::ParserError
      {}
    end
  end
end
