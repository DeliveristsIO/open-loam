class CreateLoamWebhookEndpoints < ActiveRecord::Migration[8.1]
  def change
    create_table :loam_webhook_endpoints do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }
      t.string :url, null: false
      t.string :event_pattern, null: false
      t.string :secret, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :loam_webhook_endpoints, %i[tenant_id active]
  end
end
