class CreateOpenLoamComments < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_comments<%= open_loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      t.string :commentable_type, null: false
      t.<%= open_loam_key_column_type %> :commentable_id<%= open_loam_key_limit_option %>, null: false
      t.references :author, null: false, foreign_key: { to_table: :users }<%= open_loam_type_option %>
      t.text :body, null: false
      t.timestamps
    end
    add_index :open_loam_comments, %i[tenant_id commentable_type commentable_id]
  end
end
