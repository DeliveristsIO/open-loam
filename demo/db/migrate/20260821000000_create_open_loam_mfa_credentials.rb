class CreateLoamMfaCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :loam_mfa_credentials do |t|
      # Per USER, not per tenant — MFA belongs to the person (no tenant_id).
      t.references :user, null: false, foreign_key: { to_table: :users }, index: { unique: true }
      t.text :totp_secret            # encrypted at rest, user-scoped (Loam::Encryptable)
      t.text :recovery_codes         # JSON: [{ digest, used_at }], codes stored hashed
      t.datetime :activated_at       # nil until the user confirms a live code
      t.timestamps
    end
  end
end
