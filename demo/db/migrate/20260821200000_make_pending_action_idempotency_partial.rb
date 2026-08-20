class MakePendingActionIdempotencyPartial < ActiveRecord::Migration[8.1]
  def change
    # Only ONE PENDING row per proposal per tenant — a rejected/executed row with
    # the same key may coexist, so a rejected proposal can be re-staged later.
    remove_index :loam_pending_actions, column: %i[tenant_id idempotency_key], unique: true
    add_index :loam_pending_actions, %i[tenant_id idempotency_key], unique: true,
              where: "status = 'pending'", name: "index_loam_pending_actions_pending_key"
  end
end
