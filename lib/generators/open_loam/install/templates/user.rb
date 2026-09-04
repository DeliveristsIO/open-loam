# Minimal actor model. Deliberately NOT tenant-scoped: a user can belong to
# many tenants via OpenLoam::Membership (role is per tenant). Swap in your real
# auth (Devise, OmniAuth, SSO) later — OpenLoam only needs an `id` and, for the
# bundled admin login, something that answers `authenticate_by`.
class User < ApplicationRecord
  # OpenLoam's foreign keys point at this table, so its key has to be generated
  # the same way theirs are when the app does not use integer keys.
  include OpenLoam::GeneratedKey

  has_secure_password

  has_many :open_loam_memberships, class_name: "OpenLoam::Membership"

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true

  # Email is the login, so it must mean the same thing however it was typed.
  # `normalizes` applies on write AND to finders, so User.authenticate_by and
  # find_by match a mixed-case address without callers downcasing anything.
  normalizes :email, with: ->(email) { email.to_s.strip.downcase }
end
