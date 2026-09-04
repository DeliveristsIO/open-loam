module Loam
  # A per-tenant managed lookup list — a named set of entries (e.g.
  # "damage_severity" → minor/major/critical). Admins curate the values without a
  # code deploy, and a Loam::FieldDefinition of type "dictionary" can point a
  # custom field at one. Tenant-scoped and audited like every Loam entity; see
  # Loam::Dictionaries for the read API.
  class Dictionary < Loam::TenantRecord
    self.table_name = "loam_dictionaries"

    include Loam::Auditable

    has_many :entries, class_name: "Loam::DictionaryEntry",
             foreign_key: :dictionary_id, dependent: :delete_all

    validates :key, presence: true, uniqueness: { scope: :tenant_id }
    validates :name, presence: true

    normalizes :key, with: ->(key) { key.to_s.strip.presence }
  end
end
