module OpenLoam
  # One event on its way to one endpoint. The ROW is the record of intent: it is
  # written in the publishing transaction, the job only accelerates it, and the
  # sweep finishes whatever a lost job left behind.
  #
  # pending -> sending -> succeeded | failed | (pending again, with next_attempt_at)
  # pending -> cancelled (endpoint switched off, or the host's body builder skipped it)
  class WebhookDelivery < OpenLoam::TenantRecord
    self.table_name = "open_loam_webhook_deliveries"

    STATUSES = %w[pending sending succeeded failed cancelled].freeze
    FINAL_STATUSES = %w[succeeded failed cancelled].freeze

    belongs_to :endpoint, class_name: "OpenLoam::WebhookEndpoint", inverse_of: :deliveries

    validates :event_id, :event_name, :delivery_id, presence: true
    validates :status, inclusion: { in: STATUSES }

    before_validation on: :create do
      self.delivery_id ||= "whd_#{SecureRandom.hex(12)}"
    end

    scope :due, ->(now = Time.current) { where(status: "pending").where("next_attempt_at IS NULL OR next_attempt_at <= ?", now) }
    # Pending rows the job should already have taken: never attempted for a
    # minute, or past their backoff. Fresh rows are left to their own job.
    scope :overdue, ->(now = Time.current) {
      where(status: "pending").where("(next_attempt_at IS NULL AND created_at <= ?) OR next_attempt_at <= ?", now - 60, now)
    }
    scope :stuck, ->(now = Time.current) { where(status: "sending").where("sending_at < ?", now - OpenLoam::Webhooks.stuck_after) }
    scope :prunable, ->(now, retention) { where(status: FINAL_STATUSES).where("updated_at < ?", now - retention) }
    scope :recent_first, -> { order(created_at: :desc, id: :desc) }

    def payload_hash
      value = self[:payload]
      value.is_a?(String) ? JSON.parse(value) : (value || {})
    end

    def final? = FINAL_STATUSES.include?(status)
  end
end
