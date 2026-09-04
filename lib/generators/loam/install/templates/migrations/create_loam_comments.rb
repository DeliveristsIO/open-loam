class CreateLoamComments < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :loam_comments<%= loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }<%= loam_type_option %>
      t.string :commentable_type, null: false
      t.<%= loam_key_column_type %> :commentable_id<%= loam_key_limit_option %>, null: false
      t.references :author, null: false, foreign_key: { to_table: :users }<%= loam_type_option %>
      t.text :body, null: false
      t.timestamps
    end
    add_index :loam_comments, %i[tenant_id commentable_type commentable_id]
  end
end
