class CreateOpenLoamMfaCredentials < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_mfa_credentials<%= open_loam_id_option %> do |t|
      # Per USER, not per tenant — MFA belongs to the person (no tenant_id).
      t.references :user, null: false, foreign_key: { to_table: :users }, index: { unique: true }<%= open_loam_type_option %>
      t.text :totp_secret            # encrypted at rest, user-scoped (OpenLoam::Encryptable)
      t.text :recovery_codes         # JSON: [{ digest, used_at }], codes stored hashed
      t.datetime :activated_at       # nil until the user confirms a live code
      t.bigint :last_totp_step       # last accepted TOTP timestep — rejects replays
      t.timestamps
    end
  end
end
