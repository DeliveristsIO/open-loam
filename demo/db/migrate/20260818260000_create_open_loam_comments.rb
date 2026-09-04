class CreateLoamComments < ActiveRecord::Migration[8.1]
  def change
    create_table :loam_comments do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }
      t.string :commentable_type, null: false
      t.bigint :commentable_id, null: false
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.timestamps
    end
    add_index :loam_comments, %i[tenant_id commentable_type commentable_id]
  end
end
