class CreateOpenLoamInboundWebhooks < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_inbound_webhook_sources<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.string :name, null: false
      t.string :token, null: false                 # unguessable URL id: /webhooks/:token
      t.string :secret, null: false                # HMAC key (authenticates the call)
      t.string :signature_header, null: false, default: "X-OpenLoam-Signature"
      t.string :timestamp_header                   # optional: enables the freshness window
      t.integer :timestamp_tolerance               # seconds; nil = default 300
      t.string :event_name, null: false            # what to publish on the bus
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :open_loam_inbound_webhook_sources, :token, unique: true

    create_table :open_loam_inbound_webhook_deliveries<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.references :source, null: false, foreign_key: { to_table: :open_loam_inbound_webhook_sources }<%= open_loam_type_option %>
      t.string :external_id, null: false           # delivery-id header, or a body hash
      t.string :event_name, null: false
      t.string :status, null: false, default: "received"
      t.datetime :received_at
      t.json :payload, null: false
      t.timestamps
    end
    # The idempotency ledger: a replayed (source, external_id) can't be inserted twice.
    add_index :open_loam_inbound_webhook_deliveries, %i[source_id external_id], unique: true
  end
end
