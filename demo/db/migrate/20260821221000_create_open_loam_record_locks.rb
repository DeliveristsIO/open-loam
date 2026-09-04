class CreateOpenLoamRecordLocks < ActiveRecord::Migration[8.1]
  def change
    create_table :open_loam_record_locks do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }
      t.string :lockable_type, null: false
      t.bigint :lockable_id, null: false
      t.references :locked_by, null: false, foreign_key: { to_table: :users }
      t.string :token, null: false
      t.datetime :expires_at, null: false   # TTL; an expired lock is treated as free
      t.timestamps                          # updated_at is the heartbeat
    end
    # One advisory lock per record.
    add_index :open_loam_record_locks, %i[tenant_id lockable_type lockable_id], unique: true,
              name: "index_loam_record_locks_on_lockable"
  end
end
