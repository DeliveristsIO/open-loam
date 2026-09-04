module Loam
  # A single failed authentication attempt, for rate-limiting/lockout
  # (Loam::AuthThrottle). Deliberately NOT tenant-scoped — authentication happens
  # BEFORE a tenant is chosen (login), so this is a global auth-layer table keyed
  # by the submitted identifier (the same reason Loam::MfaCredential is global).
  # Allowlisted in the guardrails tenancy lint.
  class AuthAttempt < ApplicationRecord
    include Loam::GeneratedKey
    self.table_name = "loam_auth_attempts"

    validates :identifier, :kind, presence: true
  end
end
