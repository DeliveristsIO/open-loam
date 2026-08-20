class AddDeletedAtToEquipmentAndDamageReports < ActiveRecord::Migration[8.1]
  def change
    add_column :equipment, :deleted_at, :datetime
    add_index :equipment, :deleted_at

    add_column :damage_reports, :deleted_at, :datetime
    add_index :damage_reports, :deleted_at
  end
end
