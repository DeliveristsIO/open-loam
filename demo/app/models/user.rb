# Minimal actor model. Deliberately NOT tenant-scoped: a user can belong to
# many tenants via Loam::Membership (role is per tenant). Swap in your real
# auth (Devise, OmniAuth, SSO) later — Loam only needs an `id` and, for the
# bundled admin login, something that answers `authenticate_by`.
class User < ApplicationRecord
  has_secure_password

  has_many :loam_memberships, class_name: "Loam::Membership"

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true

  # Email is the login, so it must mean the same thing however it was typed.
  # `normalizes` applies on write AND to finders, so User.authenticate_by and
  # find_by match a mixed-case address without callers downcasing anything.
  normalizes :email, with: ->(email) { email.to_s.strip.downcase }
end
