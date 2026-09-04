class CreateLoamApiTokens < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :loam_api_tokens<%= loam_id_option %> do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :loam_tenants }<%= loam_type_option %>
      t.references :user, null: false, foreign_key: true<%= loam_type_option %>
      t.string :token, null: false
      t.string :label
      t.datetime :last_used_at
      t.timestamps
    end
    # Tokens are looked up before a tenant is known, so the uniqueness that
    # matters is global.
    add_index :loam_api_tokens, :token, unique: true
  end
end
