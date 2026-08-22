class CreateCompanies < ActiveRecord::Migration[8.2]
  def change
    create_table :companies do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }
      t.string :name
      t.string :industry
      t.string :tier
      t.json :custom_fields, null: false, default: {}
      t.datetime :deleted_at
      t.integer :lock_version, null: false, default: 0   # optimistic locking (Loam::RecordLock)
      t.timestamps
    end
    # Loam::SoftDeletable filters `deleted_at IS NULL` on every query.
    add_index :companies, :deleted_at
  end
end
