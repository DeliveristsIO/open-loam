class CreateLoamDashboardWidgets < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :loam_dashboard_widgets<%= loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }<%= loam_type_option %>
      t.string :widget_key, null: false   # a registered Loam::Widgets key
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :loam_dashboard_widgets, %i[tenant_id widget_key], unique: true
  end
end
