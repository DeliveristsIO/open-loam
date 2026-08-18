class Create<%= table_name.camelize %> < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :<%= table_name %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }
<% attributes.each do |attribute| -%>
      t.<%= attribute.type %> :<%= attribute.name %>
<% end -%>
      t.json :custom_fields, null: false, default: {}
      t.timestamps
    end
  end
end
