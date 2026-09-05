require "openssl"

# Existing tokens keep working: the digest is derived from the stored plaintext
# before the column is dropped, so nobody has to reissue.
class HashOpenLoamApiTokens < ActiveRecord::Migration[8.2]
  def up
    add_column :open_loam_api_tokens, :token_digest, :string

    say_with_time "backfilling token_digest" do
      select_all("SELECT id, token FROM open_loam_api_tokens").each do |row|
        digest = OpenSSL::Digest::SHA256.hexdigest(row["token"].to_s)
        execute("UPDATE open_loam_api_tokens SET token_digest = #{connection.quote(digest)} " \
                "WHERE id = #{connection.quote(row['id'])}")
      end
    end

    change_column_null :open_loam_api_tokens, :token_digest, false
    add_index :open_loam_api_tokens, :token_digest, unique: true
    remove_index :open_loam_api_tokens, :token
    remove_column :open_loam_api_tokens, :token
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "the plaintext tokens are gone by design"
  end
end
