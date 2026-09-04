class CreateLoamAuditRecords < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :loam_audit_records<%= loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }<%= loam_type_option %>
      t.string :auditable_type, null: false
      t.<%= loam_key_column_type %> :auditable_id<%= loam_key_limit_option %>, null: false
      t.string :action, null: false
      t.<%= loam_key_column_type %> :actor_id<%= loam_key_limit_option %>
      t.text :changeset
      t.timestamps
    end
    add_index :loam_audit_records, %i[tenant_id auditable_type auditable_id]
  end
end
