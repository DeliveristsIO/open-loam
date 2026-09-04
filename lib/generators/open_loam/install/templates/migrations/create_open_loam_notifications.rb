class CreateOpenLoamNotifications < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_notifications<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.references :user, null: false, foreign_key: true<%= open_loam_type_option %>
      t.string :title, null: false
      t.text :body
      t.datetime :read_at
      t.string :source_type
      t.<%= open_loam_key_column_type %> :source_id<%= open_loam_key_limit_option %>
      t.timestamps
    end
    add_index :open_loam_notifications, %i[tenant_id user_id read_at]
  end
end
