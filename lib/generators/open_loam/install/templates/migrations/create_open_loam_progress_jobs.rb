class CreateOpenLoamProgressJobs < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_progress_jobs<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.string :key                                   # optional caller-chosen id (e.g. "reindex:Gadget")
      t.string :name, null: false                     # human label
      t.string :status, null: false, default: "running"  # running / completed / failed / cancelled
      t.integer :total, null: false, default: 0
      t.integer :completed, null: false, default: 0
      t.text :message                                 # latest status line
      t.text :error                                   # set when failed
      t.<%= open_loam_key_column_type %> :actor_id<%= open_loam_key_limit_option %>                              # who started it
      t.datetime :started_at
      t.datetime :finished_at
      t.json :result                                  # structured result for a finished job (e.g. an import summary)
      t.timestamps                                    # updated_at is the heartbeat
    end
    add_index :open_loam_progress_jobs, %i[tenant_id status]
  end
end
