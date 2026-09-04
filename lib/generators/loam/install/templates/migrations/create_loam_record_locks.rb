class CreateLoamRecordLocks < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :loam_record_locks<%= loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }<%= loam_type_option %>
      t.string :lockable_type, null: false
      t.<%= loam_key_column_type %> :lockable_id<%= loam_key_limit_option %>, null: false
      t.references :locked_by, null: false, foreign_key: { to_table: :users }<%= loam_type_option %>
      t.string :token, null: false
      t.datetime :expires_at, null: false   # TTL; an expired lock is treated as free
      t.timestamps                          # updated_at is the heartbeat
    end
    # One advisory lock per record.
    add_index :loam_record_locks, %i[tenant_id lockable_type lockable_id], unique: true,
              name: "index_loam_record_locks_on_lockable"
  end
end
