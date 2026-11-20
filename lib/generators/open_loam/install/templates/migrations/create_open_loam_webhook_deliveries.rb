class CreateOpenLoamWebhookDeliveries < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_webhook_deliveries<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.references :endpoint, null: false, foreign_key: { to_table: :open_loam_webhook_endpoints, on_delete: :cascade }<%= open_loam_type_option %>
      t.string :event_id, null: false          # one per published event, shared by its endpoints
      t.string :delivery_id, null: false       # one per (event, endpoint), sent as a header
      t.string :event_name, null: false
      t.json :payload, null: false             # the event payload (ids and scalars)
      t.string :status, null: false, default: "pending" # pending | sending | succeeded | failed | cancelled
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.datetime :sending_at
      t.integer :last_response_code
      t.string :last_error
      t.integer :last_duration_ms
      t.string :response_excerpt, limit: 512
      t.datetime :delivered_at
      t.timestamps
    end
    add_index :open_loam_webhook_deliveries, %i[endpoint_id event_id], unique: true
    add_index :open_loam_webhook_deliveries, :delivery_id, unique: true
    add_index :open_loam_webhook_deliveries, %i[tenant_id status next_attempt_at]
    add_index :open_loam_webhook_deliveries, %i[endpoint_id created_at]
    # The per-minute cross-tenant sweep lookup (overdue / stuck / prunable).
    add_index :open_loam_webhook_deliveries, %i[status next_attempt_at]
    add_index :open_loam_webhook_deliveries, %i[status updated_at]
  end
end
