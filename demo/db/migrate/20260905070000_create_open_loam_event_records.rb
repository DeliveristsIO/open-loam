class CreateOpenLoamEventRecords < ActiveRecord::Migration[8.2]
  def change
    create_table :open_loam_event_records do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }
      t.string :name, null: false                  # "rental.equipment.created"
      t.json :payload, null: false                 # JSON-scalar event payload, as published
      t.datetime :occurred_at, null: false         # when it was published, not when the row was written
      t.timestamps
    end
    add_index :open_loam_event_records, %i[tenant_id name occurred_at]
  end
end
