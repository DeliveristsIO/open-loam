# Minimal actor model. Deliberately NOT tenant-scoped: a user can belong to
# many tenants via Loam::Membership (role is per tenant). Replace with your
# real auth (Devise etc.) later — Loam only requires an `id`.
class User < ApplicationRecord
  has_many :loam_memberships, class_name: "Loam::Membership"

  validates :name, presence: true
end
