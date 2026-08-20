class CreateCustomers < ActiveRecord::Migration[8.2]
  def change
    create_table :customers do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }
      t.string :name
      t.text :email   # encrypted at rest (Loam::Encryptable) — text, since ciphertext outgrows varchar
      t.text :tax_id   # encrypted at rest (Loam::Encryptable) — text, since ciphertext outgrows varchar
      t.string :email_hash   # per-tenant blind index of :email, for exact-match lookup
      t.json :custom_fields, null: false, default: {}
      t.datetime :deleted_at
      t.timestamps
    end
    # Loam::SoftDeletable filters `deleted_at IS NULL` on every query.
    add_index :customers, :deleted_at
    add_index :customers, :email_hash
  end
end
