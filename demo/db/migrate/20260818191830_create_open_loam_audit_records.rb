class CreateLoamAuditRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :loam_audit_records do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }
      t.string :auditable_type, null: false
      t.bigint :auditable_id, null: false
      t.string :action, null: false
      t.bigint :actor_id
      t.text :changeset
      t.timestamps
    end
    add_index :loam_audit_records, %i[tenant_id auditable_type auditable_id]
  end
end
