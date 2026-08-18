class AddCustomFieldsToEquipmentAndDamageReports < ActiveRecord::Migration[8.1]
  def change
    add_column :equipment, :custom_fields, :json, null: false, default: {}
    add_column :damage_reports, :custom_fields, :json, null: false, default: {}
  end
end
