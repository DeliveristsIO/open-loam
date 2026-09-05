module OpenLoam
  # One captured domain event (see OpenLoam::EventLog). Where
  # OpenLoam::EventDelivery records that a durable subscriber was told, this
  # records that the thing happened at all.
  #
  # Append-only: a persisted row is readonly, so retention must delete_all
  # rather than destroy.
  class EventRecord < OpenLoam::TenantRecord
    self.table_name = "open_loam_event_records"

    validates :name, :occurred_at, presence: true

    scope :chronological, -> { order(:occurred_at, :id) }

    # ESCAPE is load-bearing: sanitize_sql_like backslash-escapes `_`, and SQLite
    # has no default escape character, so "damage_report." would search for a
    # literal backslash and silently match nothing.
    scope :matching, ->(name_or_prefix) {
      pattern = name_or_prefix.to_s
      if pattern.end_with?(".")
        where("name LIKE ? ESCAPE ?", "#{sanitize_sql_like(pattern)}%", "\\")
      else
        where(name: pattern)
      end
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
