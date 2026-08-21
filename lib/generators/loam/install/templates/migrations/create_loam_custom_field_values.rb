class CreateLoamCustomFieldValues < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :loam_custom_field_values do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }
      t.string :indexable_type, null: false
      t.bigint :indexable_id, null: false
      t.string :field_key, null: false
      t.text :value_text                # canonical string form (contains/present/eq)
      t.decimal :value_number           # integer/decimal fields (range queries)
      t.boolean :value_boolean          # boolean fields
      t.datetime :value_datetime        # date/datetime fields
      t.timestamps
    end
    add_index :loam_custom_field_values, %i[indexable_type indexable_id field_key],
              unique: true, name: "index_loam_cfv_unique"
    add_index :loam_custom_field_values, %i[tenant_id indexable_type field_key value_text], name: "index_loam_cfv_text"
    add_index :loam_custom_field_values, %i[tenant_id indexable_type field_key value_number], name: "index_loam_cfv_number"
  end
end
