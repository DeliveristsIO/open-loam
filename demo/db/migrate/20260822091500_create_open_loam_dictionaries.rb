class CreateLoamDictionaries < ActiveRecord::Migration[8.1]
  def change
    create_table :loam_dictionaries do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }
      t.string :key, null: false   # the code the field def / API references (e.g. "damage_severity")
      t.string :name, null: false  # human label for the list
      t.timestamps
    end
    add_index :loam_dictionaries, %i[tenant_id key], unique: true
  end
end
