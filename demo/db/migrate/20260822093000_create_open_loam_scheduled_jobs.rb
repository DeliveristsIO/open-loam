class CreateOpenLoamScheduledJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :open_loam_scheduled_jobs do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }
      t.string :key, null: false                        # unique per tenant
      t.string :name, null: false
      t.string :job_class, null: false                  # a whitelisted ActiveJob class name
      t.string :schedule, null: false                   # "0 7 * * *" or "interval:3600"
      t.string :timezone                                # IANA zone; UTC when blank
      t.string :scope, null: false, default: "tenant"   # "tenant" (per-tenant) or "system" (once)
      t.datetime :next_run_at
      t.datetime :last_run_at
      t.datetime :locked_until                          # the atomic-claim lock (no double-fire)
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :open_loam_scheduled_jobs, %i[tenant_id key], unique: true
    # The tick scans by due-and-unlocked across all tenants.
    add_index :open_loam_scheduled_jobs, %i[active next_run_at locked_until]
  end
end
