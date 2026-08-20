class AddLastTotpStepToMfaCredentials < ActiveRecord::Migration[8.1]
  def change
    # The last accepted TOTP timestep — a code whose step is not strictly greater
    # is a replay and is rejected (at login and at sudo).
    add_column :loam_mfa_credentials, :last_totp_step, :bigint
  end
end
