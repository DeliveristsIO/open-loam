class AddConfigToLoamFieldDefinitions < ActiveRecord::Migration[8.1]
  def change
    # Type-specific settings for a field definition (e.g. a dictionary field's key).
    add_column :loam_field_definitions, :config, :json, null: false, default: {}
  end
end
