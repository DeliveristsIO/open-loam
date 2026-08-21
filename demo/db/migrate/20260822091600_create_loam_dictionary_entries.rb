class CreateLoamDictionaryEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :loam_dictionary_entries do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }
      t.references :dictionary, null: false, foreign_key: { to_table: :loam_dictionaries }
      t.string :value, null: false                    # the stored code
      t.string :label, null: false                    # display text
      t.string :color                                 # optional hex
      t.string :icon                                  # optional icon name
      t.integer :position, null: false, default: 0    # ordering
      t.boolean :is_default, null: false, default: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :loam_dictionary_entries, %i[dictionary_id value], unique: true
    add_index :loam_dictionary_entries, %i[tenant_id dictionary_id position]
  end
end
