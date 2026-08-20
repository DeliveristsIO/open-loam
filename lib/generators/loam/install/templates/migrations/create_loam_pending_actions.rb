class CreateLoamPendingActions < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :loam_pending_actions do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }
      t.bigint :actor_id                       # who staged it (the proposer)
      t.string :status, null: false, default: "pending"
      t.string :action_type, null: false       # create / update / destroy
      t.string :target_type                     # the model being mutated
      t.bigint :target_id                       # null for a staged create
      t.text :changeset                         # encrypted JSON of the proposed changes
      t.text :summary, null: false              # human-readable description
      t.string :idempotency_key, null: false    # keyed HMAC; same proposal collapses to one row
      t.bigint :reviewed_by_id                  # the approving/rejecting manager
      t.datetime :reviewed_at
      t.text :result                            # execution outcome, or "rejected: <reason>"
      t.text :error                             # execution failure message
      t.timestamps
    end
    # One row per distinct proposal per tenant.
    # Only ONE PENDING row per proposal per tenant — a rejected/executed row with
    # the same key may coexist, so a rejected proposal can be re-staged later.
    add_index :loam_pending_actions, %i[tenant_id idempotency_key], unique: true,
              where: "status = 'pending'", name: "index_loam_pending_actions_pending_key"
    add_index :loam_pending_actions, %i[tenant_id status]
  end
end
