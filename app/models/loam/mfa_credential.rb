require "bcrypt"

module Loam
  # A user's multi-factor credential: a TOTP secret plus single-use recovery
  # codes. Deliberately NOT tenant-scoped — MFA belongs to the PERSON, who spans
  # tenants, and the second-factor challenge runs at login BEFORE any tenant is
  # chosen. So the secret is encrypted under a USER-scoped key (Loam::Encryptable
  # `scope:`), which decrypts in any tenant and with no tenant at all — the whole
  # reason a per-tenant key would be a lockout bug here.
  class MfaCredential < ApplicationRecord
    self.table_name = "loam_mfa_credentials"

    RECOVERY_CODE_COUNT = 10

    belongs_to :user

    include Loam::Encryptable
    encrypts :totp_secret, scope: ->(credential) { "user/#{credential.user_id}" }

    # Recovery codes are stored HASHED (BCrypt), never in the clear: [{ "digest",
    # "used_at" }]. The plaintext is shown once, at generation, and then only the
    # user has it.
    serialize :recovery_codes, coder: JSON, type: Array

    validates :user_id, uniqueness: true

    # The active credential for a user, or nil — nil while enrollment is pending
    # (a secret exists but was never confirmed) so an un-activated credential
    # never gates login.
    def self.active_for(user)
      return nil unless user

      credential = find_by(user_id: user.id)
      credential&.activated? ? credential : nil
    end

    def activated?
      activated_at.present?
    end

    # Confirm enrollment against a CANDIDATE secret (held in the session, never
    # written until proven) with a live code, then activate: adopt the secret,
    # mint recovery codes, and record the confirming step so it cannot be
    # replayed at the next login. Returns the plaintext codes (shown ONCE) or nil
    # if the code is wrong. The old secret stays valid until this succeeds, so a
    # half-finished re-enrollment never downgrades an active credential.
    def activate_with!(candidate_secret, code)
      step = Loam::Totp.matching_step(candidate_secret, code)
      return nil unless step

      self.totp_secret = candidate_secret
      self.activated_at = Time.current
      self.last_totp_step = step
      plaintext = mint_recovery_codes!
      save!
      plaintext
    end

    # Verify a TOTP code AND consume its timestep, so a captured code cannot be
    # replayed within its ~90s validity window (at login or at sudo). The lock +
    # last_totp_step check closes the read-modify-write race of two concurrent
    # submits. On SQLite `FOR UPDATE` is dropped (writer serialization + the
    # re-check still hold); Postgres takes a real row lock.
    def verify_totp(code)
      return false unless activated?

      with_lock do
        step = Loam::Totp.matching_step(totp_secret, code)
        if step && (last_totp_step.nil? || step > last_totp_step)
          update!(last_totp_step: step)
          true
        else
          false
        end
      end
    end

    # Consume a recovery code: valid exactly once. with_lock reloads and
    # re-checks inside the transaction, so two concurrent submits of the same
    # code cannot both succeed. Constant-time per candidate via BCrypt.
    def consume_recovery_code(code)
      code = code.to_s.strip.downcase
      return false if code.empty?

      with_lock do
        entry = recovery_codes.find { |e| e["used_at"].nil? && BCrypt::Password.new(e["digest"]) == code }
        if entry
          entry["used_at"] = Time.current.iso8601
          save!
          true
        else
          false
        end
      end
    end

    def unused_recovery_code_count
      recovery_codes.count { |e| e["used_at"].nil? }
    end

    def provisioning_uri(issuer:)
      Loam::Totp.provisioning_uri(totp_secret, account: user.email, issuer: issuer)
    end

    private

    def mint_recovery_codes!
      plaintext = Array.new(RECOVERY_CODE_COUNT) { SecureRandom.alphanumeric(10).downcase }
      self.recovery_codes = plaintext.map { |code| { "digest" => BCrypt::Password.create(code), "used_at" => nil } }
      plaintext
    end
  end
end
