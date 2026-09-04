class CreateLoamWebhookEndpoints < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :loam_webhook_endpoints<%= loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }<%= loam_type_option %>
      t.string :url, null: false
      t.string :event_pattern, null: false
      t.string :secret, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :loam_webhook_endpoints, %i[tenant_id active]
  end
end
