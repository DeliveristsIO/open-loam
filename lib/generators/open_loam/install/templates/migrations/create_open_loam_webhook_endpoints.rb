class CreateOpenLoamWebhookEndpoints < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_webhook_endpoints<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.string :url, null: false
      t.string :event_pattern, null: false
      t.string :secret, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :open_loam_webhook_endpoints, %i[tenant_id active]
  end
end
