class CreateOpenLoamMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :open_loam_memberships do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false
      t.timestamps
    end
    add_index :open_loam_memberships, %i[tenant_id user_id], unique: true
  end
end
