module OpenLoam
  # A read-model projection of ONE custom field of ONE record into typed,
  # INDEXED columns — so filtering/sorting/searching on a custom field is
  # index-backed instead of a per-row JSON extraction over the `custom_fields`
  # column (which can't be indexed and full-scans at scale). One row per
  # (record, custom field); maintained by OpenLoam::CustomFieldIndex from the
  # OpenLoam::CustomFields save/destroy hooks. Tenant-scoped.
  #
  # The value is written into the column matching the field's declared type
  # (value_number / value_boolean / value_datetime) AND always into value_text
  # (its string form) for text ops (contains/present) and canonical equality.
  class CustomFieldValue < OpenLoam::TenantRecord
    self.table_name = "open_loam_custom_field_values"

    validates :indexable_type, :indexable_id, :field_key, presence: true
    validates :field_key, uniqueness: { scope: %i[indexable_type indexable_id] }
  end
end
