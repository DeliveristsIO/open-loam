class CreateOpenLoamMemberships < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_memberships<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.references :user, null: false, foreign_key: true<%= open_loam_type_option %>
      t.string :role, null: false
      t.timestamps
    end
    add_index :open_loam_memberships, %i[tenant_id user_id], unique: true
  end
end
