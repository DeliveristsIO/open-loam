module OpenLoam
  # A per-locale override for ONE field of ONE record — the storage behind
  # OpenLoam::Translatable. The record's own column holds the base (default-locale)
  # value; a translation row overrides it for a specific locale. Additive:
  # writing a translation never touches the base column, so the base value is
  # never lost. Tenant-scoped and audited.
  class Translation < OpenLoam::TenantRecord
    self.table_name = "open_loam_translations"

    include OpenLoam::Auditable

    belongs_to :translatable, polymorphic: true

    validates :locale, :field, presence: true
    validates :field, uniqueness: { scope: %i[translatable_type translatable_id locale] }
  end
end
