class CreateOpenLoamDictionaryEntries < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_dictionary_entries<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.references :dictionary, null: false, foreign_key: { to_table: :open_loam_dictionaries }<%= open_loam_type_option %>
      t.string :value, null: false                    # the stored code
      t.string :label, null: false                    # display text
      t.string :color                                 # optional hex
      t.string :icon                                  # optional icon name
      t.integer :position, null: false, default: 0    # ordering
      t.boolean :is_default, null: false, default: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :open_loam_dictionary_entries, %i[dictionary_id value], unique: true
    add_index :open_loam_dictionary_entries, %i[tenant_id dictionary_id position]
  end
end
