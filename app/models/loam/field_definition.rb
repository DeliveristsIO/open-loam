module Loam
  # Runtime declaration of a migration-free field on a tenant-scoped entity —
  # "entity_type Equipment gets a field called serial_number of type string,
  # writable by managers only." Tenant-scoped like everything else: a field
  # defined in one tenant is invisible to another's records of the same
  # entity_type, and definitions are the ONLY way values in an entity's
  # `custom_fields` json column get read/written (see Loam::CustomFields).
  class FieldDefinition < Loam::TenantRecord
    self.table_name = "loam_field_definitions"

    FIELD_TYPES = %w[string text integer decimal boolean date datetime dictionary].freeze

    validates :entity_type, presence: true
    validates :name, presence: true, uniqueness: { scope: %i[tenant_id entity_type] }
    validates :field_type, presence: true, inclusion: { in: FIELD_TYPES }
    validate :dictionary_key_resolves, if: -> { field_type == "dictionary" }

    # The `config` json holds type-specific settings. For a "dictionary" field it
    # carries the key of the Loam::Dictionary whose entries populate the select.
    def dictionary_key
      config.is_a?(Hash) ? config["dictionary"] : nil
    end

    def dictionary_key=(value)
      base = config.is_a?(Hash) ? config : {}
      self.config = base.merge("dictionary" => value.to_s.strip.presence)
    end

    private

    def dictionary_key_resolves
      if dictionary_key.blank?
        errors.add(:dictionary_key, "is required for a dictionary field")
      elsif Loam::Dictionaries.get(dictionary_key).nil?
        errors.add(:dictionary_key, "must name an existing dictionary in this tenant")
      end
    end
  end
end
