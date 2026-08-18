class CreateLoamNotifications < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :loam_notifications do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :body
      t.datetime :read_at
      t.string :source_type
      t.bigint :source_id
      t.timestamps
    end
    add_index :loam_notifications, %i[tenant_id user_id read_at]
  end
end
