class CreateOpenLoamEventRecords < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_event_records<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.string :name, null: false                  # "rental.equipment.created"
      t.json :payload, null: false                 # JSON-scalar event payload, as published
      t.datetime :occurred_at, null: false         # publish time, not row-write time
      t.timestamps
    end
    # Matches OpenLoam::EventLog.read: tenant, then name or prefix, in time order.
    add_index :open_loam_event_records, %i[tenant_id name occurred_at]
  end
end
