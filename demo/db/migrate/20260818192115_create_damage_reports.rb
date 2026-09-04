class CreateDamageReports < ActiveRecord::Migration[8.1]
  def change
    create_table :damage_reports do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }
      t.integer :equipment_id
      t.text :description
      t.boolean :approved
      t.timestamps
    end
  end
end
