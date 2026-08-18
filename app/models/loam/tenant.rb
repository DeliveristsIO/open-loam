module Loam
  # The tenant itself is deliberately NOT tenant-scoped — it is the axis the
  # rest of the system is scoped by.
  class Tenant < ActiveRecord::Base
    self.table_name = "loam_tenants"

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true

    has_many :memberships, class_name: "Loam::Membership", dependent: :delete_all
  end
end
