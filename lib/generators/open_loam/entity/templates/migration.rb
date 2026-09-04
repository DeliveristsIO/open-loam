class Create<%= table_name.camelize %> < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :<%= table_name %><%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
<% attributes.each do |attribute| -%>
<% if encrypted?(attribute) -%>
      t.text :<%= attribute.name %>   # encrypted at rest (OpenLoam::Encryptable) — text, since ciphertext outgrows varchar
<% else -%>
      t.<%= attribute.type %> :<%= attribute.name %>
<% end -%>
<% end -%>
<% encrypt_searchable_names.each do |field| -%>
      t.string :<%= field %>_hash   # per-tenant blind index of :<%= field %>, for exact-match lookup
<% end -%>
      t.json :custom_fields, null: false, default: {}
      t.datetime :deleted_at
      t.integer :lock_version, null: false, default: 0   # optimistic locking (OpenLoam::RecordLock)
      t.timestamps
    end
    # OpenLoam::SoftDeletable filters `deleted_at IS NULL` on every query.
    add_index :<%= table_name %>, :deleted_at
<% encrypt_searchable_names.each do |field| -%>
    add_index :<%= table_name %>, :<%= field %>_hash
<% end -%>
  end
end
