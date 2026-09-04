class CreateLoamPerspectives < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :loam_perspectives<%= loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }<%= loam_type_option %>
      t.string :entity_type, null: false        # which entity this view is for
      t.string :name, null: false               # human label
      t.<%= loam_key_column_type %> :owner_id<%= loam_key_limit_option %>                         # the user who owns a private view
      t.string :visibility, null: false, default: "private"  # private / role / tenant
      t.string :role                             # set when visibility is "role"
      t.boolean :is_default, null: false, default: false
      t.json :config, null: false, default: {}   # { columns, filters, sort, page_size }
      t.integer :lock_version, null: false, default: 0  # optimistic locking
      t.timestamps
    end
    add_index :loam_perspectives, %i[tenant_id entity_type]
  end
end
