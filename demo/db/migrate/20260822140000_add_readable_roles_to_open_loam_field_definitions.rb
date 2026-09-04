class AddReadableRolesToOpenLoamFieldDefinitions < ActiveRecord::Migration[8.1]
  def change
    add_column :open_loam_field_definitions, :readable_roles, :json, null: false, default: []
  end
end
