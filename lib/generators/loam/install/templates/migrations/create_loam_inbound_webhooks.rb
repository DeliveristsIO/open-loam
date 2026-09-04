class CreateLoamInboundWebhooks < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :loam_inbound_webhook_sources<%= loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }<%= loam_type_option %>
      t.string :name, null: false
      t.string :token, null: false                 # unguessable URL id: /webhooks/:token
      t.string :secret, null: false                # HMAC key (authenticates the call)
      t.string :signature_header, null: false, default: "X-Loam-Signature"
      t.string :delivery_id_header                 # optional: external delivery-id for dedupe
      t.string :timestamp_header                   # optional: enables the freshness window
      t.integer :timestamp_tolerance               # seconds; nil = default 300
      t.string :event_name, null: false            # what to publish on the bus
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :loam_inbound_webhook_sources, :token, unique: true

    create_table :loam_inbound_webhook_deliveries<%= loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }<%= loam_type_option %>
      t.references :source, null: false, foreign_key: { to_table: :loam_inbound_webhook_sources }<%= loam_type_option %>
      t.string :external_id, null: false           # delivery-id header, or a body hash
      t.string :event_name, null: false
      t.string :status, null: false, default: "received"
      t.datetime :received_at
      t.json :payload, null: false
      t.timestamps
    end
    # The idempotency ledger: a replayed (source, external_id) can't be inserted twice.
    add_index :loam_inbound_webhook_deliveries, %i[source_id external_id], unique: true
  end
end
