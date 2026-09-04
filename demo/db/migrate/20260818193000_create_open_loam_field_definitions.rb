class CreateOpenLoamFieldDefinitions < ActiveRecord::Migration[8.1]
  def change
    create_table :open_loam_field_definitions do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }
      t.string :entity_type, null: false
      t.string :name, null: false
      t.string :field_type, null: false
      t.json :writable_roles, default: [], null: false
      t.timestamps
    end
    add_index :open_loam_field_definitions, %i[tenant_id entity_type name], unique: true, name: "index_loam_field_definitions_on_tenant_entity_name"
  end
end
