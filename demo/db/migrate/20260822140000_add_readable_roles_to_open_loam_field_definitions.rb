class AddReadableRolesToLoamFieldDefinitions < ActiveRecord::Migration[8.1]
  def change
    add_column :loam_field_definitions, :readable_roles, :json, null: false, default: []
  end
end
