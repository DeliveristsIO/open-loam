module Loam
  # One option in a Loam::Dictionary: a stored `value` (the code that lands in a
  # record) plus display metadata (label, color, icon), an ordering `position`,
  # a `is_default` flag, and an `active` switch (a retired option stops being
  # offered without deleting the historical values already stored). Tenant-scoped
  # and audited.
  class DictionaryEntry < Loam::TenantRecord
    self.table_name = "loam_dictionary_entries"

    include Loam::Auditable

    belongs_to :dictionary, class_name: "Loam::Dictionary"

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
      Loam::Dictionaries.clear_cache
    end
  end
end
