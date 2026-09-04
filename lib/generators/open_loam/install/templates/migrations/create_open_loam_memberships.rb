class CreateLoamMemberships < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :loam_memberships<%= loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }<%= loam_type_option %>
      t.references :user, null: false, foreign_key: true<%= loam_type_option %>
      t.string :role, null: false
      t.timestamps
    end
    add_index :loam_memberships, %i[tenant_id user_id], unique: true
  end
end
