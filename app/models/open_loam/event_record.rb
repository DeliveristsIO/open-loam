module OpenLoam
  # One captured domain event (see OpenLoam::EventLog). The row IS the history:
  # OpenLoam::EventDelivery records that a durable subscriber was told, this
  # records that the thing happened at all.
  #
  # APPEND-ONLY. A log you can edit is not evidence, so a persisted row is
  # readonly — an UPDATE raises ActiveRecord::ReadOnlyRecord. Retention still
  # removes old rows, but through `delete_all` (which never instantiates them),
  # never destroy.
  class EventRecord < OpenLoam::TenantRecord
    self.table_name = "open_loam_event_records"

    validates :name, :occurred_at, presence: true

    scope :chronological, -> { order(:occurred_at, :id) }

    # One event name ("rental.equipment.created") or a domain prefix
    # ("rental.") — the same rule as OpenLoam::Events.subscribe and webhook
    # endpoints, so a pattern means the same thing everywhere.
    scope :matching, ->(name_or_prefix) {
      pattern = name_or_prefix.to_s
      pattern.end_with?(".") ? where("name LIKE ?", "#{sanitize_sql_like(pattern)}%") : where(name: pattern)
    }

    def readonly?
      persisted?
    end

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
