module OpenLoam
  # A single failed authentication attempt, for rate-limiting/lockout
  # (OpenLoam::AuthThrottle). Deliberately NOT tenant-scoped — authentication happens
  # BEFORE a tenant is chosen (login), so this is a global auth-layer table keyed
  # by the submitted identifier (the same reason OpenLoam::MfaCredential is global).
  # Allowlisted in the guardrails tenancy lint.
  class AuthAttempt < ApplicationRecord
    include OpenLoam::GeneratedKey
    self.table_name = "open_loam_auth_attempts"

    validates :identifier, :kind, presence: true
  end
end
