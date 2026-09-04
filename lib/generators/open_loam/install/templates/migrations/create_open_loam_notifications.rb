class CreateLoamNotifications < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :loam_notifications<%= loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }<%= loam_type_option %>
      t.references :user, null: false, foreign_key: true<%= loam_type_option %>
      t.string :title, null: false
      t.text :body
      t.datetime :read_at
      t.string :source_type
      t.<%= loam_key_column_type %> :source_id<%= loam_key_limit_option %>
      t.timestamps
    end
    add_index :loam_notifications, %i[tenant_id user_id read_at]
  end
end
