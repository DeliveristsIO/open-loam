class CreateOpenLoamNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :open_loam_notifications do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :body
      t.datetime :read_at
      t.string :source_type
      t.bigint :source_id
      t.timestamps
    end
    add_index :open_loam_notifications, %i[tenant_id user_id read_at]
  end
end
