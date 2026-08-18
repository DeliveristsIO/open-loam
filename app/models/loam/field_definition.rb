module Loam
  # Runtime declaration of a migration-free field on a tenant-scoped entity —
  # "entity_type Equipment gets a field called serial_number of type string,
  # writable by managers only." Tenant-scoped like everything else: a field
  # defined in one tenant is invisible to another's records of the same
  # entity_type, and definitions are the ONLY way values in an entity's
  # `custom_fields` json column get read/written (see Loam::CustomFields).
  class FieldDefinition < Loam::TenantRecord
    self.table_name = "loam_field_definitions"

    FIELD_TYPES = %w[string text integer decimal boolean date datetime].freeze

    validates :entity_type, presence: true
    validates :name, presence: true, uniqueness: { scope: %i[tenant_id entity_type] }
    validates :field_type, presence: true, inclusion: { in: FIELD_TYPES }
  end
end
