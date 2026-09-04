module Loam
  # A per-locale override for ONE field of ONE record — the storage behind
  # Loam::Translatable. The record's own column holds the base (default-locale)
  # value; a translation row overrides it for a specific locale. Additive:
  # writing a translation never touches the base column, so the base value is
  # never lost. Tenant-scoped and audited.
  class Translation < Loam::TenantRecord
    self.table_name = "loam_translations"

    include Loam::Auditable

    belongs_to :translatable, polymorphic: true

    validates :locale, :field, presence: true
    validates :field, uniqueness: { scope: %i[translatable_type translatable_id locale] }
  end
end
