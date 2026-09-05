class CreateOpenLoamEventRecords < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_event_records<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.string :name, null: false                  # "rental.equipment.created"
      t.json :payload, null: false                 # JSON-scalar event payload, as published
      t.datetime :occurred_at, null: false         # when it was published, not when the row was written
      t.timestamps
    end
    # The read path is always "this tenant, this name or domain prefix, in time
    # order" (OpenLoam::EventLog.read), so the index carries all three.
    add_index :open_loam_event_records, %i[tenant_id name occurred_at]
  end
end
