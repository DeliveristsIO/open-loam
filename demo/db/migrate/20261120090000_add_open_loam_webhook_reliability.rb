# 0.4.0: delivery ledger + endpoint health. Existing endpoints keep their single
# event_pattern and plaintext secret; both stay readable.
class AddOpenLoamWebhookReliability < ActiveRecord::Migration[8.2]
  def up
    change_column_null :open_loam_webhook_endpoints, :event_pattern, true
    change_column :open_loam_webhook_endpoints, :secret, :text, null: false
    add_column :open_loam_webhook_endpoints, :event_patterns, :json, null: false, default: []
    add_column :open_loam_webhook_endpoints, :previous_secret, :text
    add_column :open_loam_webhook_endpoints, :previous_secret_expires_at, :datetime
    add_column :open_loam_webhook_endpoints, :description, :string
    add_column :open_loam_webhook_endpoints, :metadata, :json, null: false, default: {}
    add_column :open_loam_webhook_endpoints, :disabled_reason, :string
    add_column :open_loam_webhook_endpoints, :consecutive_failures, :integer, null: false, default: 0
    add_column :open_loam_webhook_endpoints, :last_success_at, :datetime
    add_column :open_loam_webhook_endpoints, :last_failure_at, :datetime

    create_table :open_loam_webhook_deliveries do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }
      t.references :endpoint, null: false, foreign_key: { to_table: :open_loam_webhook_endpoints, on_delete: :cascade }
      t.string :event_id, null: false
      t.string :delivery_id, null: false
      t.string :event_name, null: false
      t.json :payload, null: false
      t.string :status, null: false, default: "pending"
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
  end

  def down
    drop_table :open_loam_webhook_deliveries
    %i[event_patterns previous_secret previous_secret_expires_at description metadata disabled_reason
       consecutive_failures last_success_at last_failure_at].each do |column|
      remove_column :open_loam_webhook_endpoints, column
    end
    change_column :open_loam_webhook_endpoints, :secret, :string, null: false
    change_column_null :open_loam_webhook_endpoints, :event_pattern, false
  end
end
