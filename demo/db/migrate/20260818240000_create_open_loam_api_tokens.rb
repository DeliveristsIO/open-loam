class CreateOpenLoamApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :open_loam_api_tokens do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }
      t.references :user, null: false, foreign_key: true
      t.string :token, null: false
      t.string :label
      t.datetime :last_used_at
      t.timestamps
    end
    # Tokens are looked up before a tenant is known, so the uniqueness that
    # matters is global.
    add_index :open_loam_api_tokens, :token, unique: true
  end
end
