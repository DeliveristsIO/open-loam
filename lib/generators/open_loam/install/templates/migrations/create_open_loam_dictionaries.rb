class CreateOpenLoamDictionaries < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_dictionaries<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.string :key, null: false   # the code the field def / API references (e.g. "damage_severity")
      t.string :name, null: false  # human label for the list
      t.timestamps
    end
    add_index :open_loam_dictionaries, %i[tenant_id key], unique: true
  end
end
