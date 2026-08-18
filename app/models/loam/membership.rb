module Loam
  # Connects an actor (the host app's User) to a tenant with a role. Roles are
  # plain strings ("manager", "employee", ...) — policies interpret them.
  # Tenant-scoped like everything else: asking for someone's role always means
  # "their role in the CURRENT tenant".
  class Membership < Loam::TenantRecord
    self.table_name = "loam_memberships"

    belongs_to :user

    validates :role, presence: true
    validates :user_id, uniqueness: { scope: :tenant_id }
  end
end
