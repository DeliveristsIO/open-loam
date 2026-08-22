class CreateLeads < ActiveRecord::Migration[8.2]
  def change
    create_table :leads do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }
      t.integer :company_id
      t.string :source
      t.decimal :value
      t.string :state
      t.json :custom_fields, null: false, default: {}
      t.datetime :deleted_at
      t.integer :lock_version, null: false, default: 0   # optimistic locking (Loam::RecordLock)
      t.timestamps
    end
    # Loam::SoftDeletable filters `deleted_at IS NULL` on every query.
    add_index :leads, :deleted_at
  end
end
