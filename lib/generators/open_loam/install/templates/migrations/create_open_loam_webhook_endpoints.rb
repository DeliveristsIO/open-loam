class CreateOpenLoamWebhookEndpoints < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_webhook_endpoints<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.string :url, null: false
      t.string :event_pattern                  # single pattern (0.3.0); nil when event_patterns is used
      t.json :event_patterns, null: false, default: []
      t.text :secret, null: false              # plaintext hex, or "v2:..." when encrypt_secrets is on
      t.text :previous_secret
      t.datetime :previous_secret_expires_at
      t.boolean :active, null: false, default: true
      t.string :description
      t.json :metadata, null: false, default: {}  # host-owned settings; OpenLoam never reads it
      t.string :disabled_reason
      t.integer :consecutive_failures, null: false, default: 0
      t.datetime :last_success_at
      t.datetime :last_failure_at
      t.timestamps
    end
    add_index :open_loam_webhook_endpoints, %i[tenant_id active]
  end
end
