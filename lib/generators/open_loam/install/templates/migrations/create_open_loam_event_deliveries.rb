class CreateOpenLoamEventDeliveries < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_event_deliveries<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.string :subscriber_key, null: false            # a registered OpenLoam::DurableEvents subscriber
      t.string :event_name, null: false
      t.json :payload, null: false                     # JSON-scalar event payload
      t.string :status, null: false, default: "pending" # pending | delivered | dead
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      t.datetime :next_attempt_at                      # backoff gate for the next retry
      t.datetime :delivered_at
      t.timestamps
    end
    add_index :open_loam_event_deliveries, %i[tenant_id status next_attempt_at]
  end
end
