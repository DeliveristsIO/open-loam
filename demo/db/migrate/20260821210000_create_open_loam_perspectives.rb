class CreateOpenLoamPerspectives < ActiveRecord::Migration[8.1]
  def change
    create_table :open_loam_perspectives do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }
      t.string :entity_type, null: false        # which entity this view is for
      t.string :name, null: false               # human label
      t.bigint :owner_id                         # the user who owns a private view
      t.string :visibility, null: false, default: "private"  # private / role / tenant
      t.string :role                             # set when visibility is "role"
      t.boolean :is_default, null: false, default: false
      t.json :config, null: false, default: {}   # { columns, filters, sort, page_size }
      t.integer :lock_version, null: false, default: 0  # optimistic locking
      t.timestamps
    end
    add_index :open_loam_perspectives, %i[tenant_id entity_type]
  end
end
