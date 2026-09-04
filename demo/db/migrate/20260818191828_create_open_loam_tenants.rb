class CreateLoamTenants < ActiveRecord::Migration[8.1]
  def change
    create_table :loam_tenants do |t|
      t.string :name, null: false
      t.string :slug, null: false, index: { unique: true }
      t.timestamps
    end
  end
end
