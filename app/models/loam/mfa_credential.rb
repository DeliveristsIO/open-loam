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

    # Begin (or restart) enrollment: a fresh secret, not yet active, no recovery
    # codes until it is confirmed. Idempotent re-enrollment, so a user who never
    # finished can simply start over instead of hitting the uniqueness index.
    def start_enrollment!
      self.totp_secret = Loam::Totp.generate_secret
      self.activated_at = nil
      self.recovery_codes = []
      save!
      self
    end

    # Confirm enrollment with a live TOTP code, then activate and mint recovery
    # codes. Returns the plaintext codes (to show ONCE) or nil if the code is
    # wrong — activating without confirming would lock the user out next login.
    def activate!(code)
      return nil unless Loam::Totp.verify(totp_secret, code)

      plaintext = mint_recovery_codes!
      update!(activated_at: Time.current)
      plaintext
    end

    def verify_totp(code)
      activated? && Loam::Totp.verify(totp_secret, code)
    end

    # Consume a recovery code: valid exactly once. Constant-time per candidate
    # via BCrypt's own comparison.
    def consume_recovery_code(code)
      code = code.to_s.strip.downcase
      return false if code.empty?

      entry = recovery_codes.find { |e| e["used_at"].nil? && BCrypt::Password.new(e["digest"]) == code }
      return false unless entry

      entry["used_at"] = Time.current.iso8601
      save!
      true
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
