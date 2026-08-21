class AddLockVersionToEntities < ActiveRecord::Migration[8.1]
  def change
    # Optimistic locking (Loam::RecordLock) for the business entities — a stale
    # update raises ActiveRecord::StaleObjectError instead of clobbering.
    add_column :equipment, :lock_version, :integer, null: false, default: 0
    add_column :damage_reports, :lock_version, :integer, null: false, default: 0
    add_column :customers, :lock_version, :integer, null: false, default: 0
  end
end
