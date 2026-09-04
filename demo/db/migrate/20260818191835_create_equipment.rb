class CreateEquipment < ActiveRecord::Migration[8.1]
  def change
    create_table :equipment do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }
      t.string :name
      t.decimal :daily_rate
      t.string :status
      t.timestamps
    end
  end
end
