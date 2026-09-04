class CreateOpenLoamAuditRecords < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_audit_records<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.string :auditable_type, null: false
      t.<%= open_loam_key_column_type %> :auditable_id<%= open_loam_key_limit_option %>, null: false
      t.string :action, null: false
      t.<%= open_loam_key_column_type %> :actor_id<%= open_loam_key_limit_option %>
      t.text :changeset
      t.timestamps
    end
    add_index :open_loam_audit_records, %i[tenant_id auditable_type auditable_id]
  end
end
