class CreateLoamFieldDefinitions < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :loam_field_definitions<%= loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }<%= loam_type_option %>
      t.string :entity_type, null: false
      t.string :name, null: false
      t.string :field_type, null: false
      t.json :writable_roles, default: [], null: false
      t.json :readable_roles, default: [], null: false  # empty = any member may read (used by the index oracle guard)
      t.json :config, null: false, default: {}  # type-specific settings (e.g. a dictionary field's key)
      t.timestamps
    end
    add_index :loam_field_definitions, %i[tenant_id entity_type name], unique: true, name: "index_loam_field_definitions_on_tenant_entity_name"
  end
end
