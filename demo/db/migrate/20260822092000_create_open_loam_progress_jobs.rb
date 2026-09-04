class CreateLoamProgressJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :loam_progress_jobs do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }
      t.string :key                                   # optional caller-chosen id (e.g. "reindex:Equipment")
      t.string :name, null: false                     # human label
      t.string :status, null: false, default: "running"  # running / completed / failed / cancelled
      t.integer :total, null: false, default: 0
      t.integer :completed, null: false, default: 0
      t.text :message                                 # latest status line
      t.text :error                                   # set when failed
      t.bigint :actor_id                              # who started it
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps                                    # updated_at is the heartbeat
    end
    add_index :loam_progress_jobs, %i[tenant_id status]
  end
end
