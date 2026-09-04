module OpenLoam
  # One option in a OpenLoam::Dictionary: a stored `value` (the code that lands in a
  # record) plus display metadata (label, color, icon), an ordering `position`,
  # a `is_default` flag, and an `active` switch (a retired option stops being
  # offered without deleting the historical values already stored). Tenant-scoped
  # and audited.
  class DictionaryEntry < OpenLoam::TenantRecord
    self.table_name = "open_loam_dictionary_entries"

    include OpenLoam::Auditable

    belongs_to :dictionary, class_name: "OpenLoam::Dictionary"

    validates :value, presence: true, uniqueness: { scope: :dictionary_id }
    validates :label, presence: true

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(:position, :id) }

    after_commit :clear_dictionary_cache
    after_destroy_commit :clear_dictionary_cache

    private

    # A within-request edit must not read a stale cached list (the cache also
    # resets per request, so this only matters when a write and a read share one).
    def clear_dictionary_cache
      OpenLoam::Dictionaries.clear_cache
    end
  end
end
