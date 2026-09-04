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

    # The other blessed cross-tenant lookup (see Loam::ApiToken.authenticate).
    # "Which tenants may this person enter?" is asked at login, before any
    # tenant is chosen, so it cannot be answered from inside one — which is why
    # it lives in the gem rather than in host app code, where reaching across
    # tenants is a guardrail failure.
    #
    # Returns a Loam::Tenant relation, so callers can order/filter it further.
    def self.tenants_for(user)
      user_id = user.respond_to?(:id) ? user.id : user

      Loam::Tenant.where(id: unscoped.where(user_id: user_id).select(:tenant_id)).order(:name)
    end
  end
end
