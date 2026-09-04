module Loam
  # A tenant's connection to an external identity provider (OIDC). Per-tenant
  # config: each tenant/org wires its OWN IdP, so the client_secret is encrypted
  # under the tenant key (the default Encryptable scope) — unlike MFA, which is
  # user-keyed. Home-realm discovery matches an email `domain` to the owning
  # provider at the sign-in page (see Loam::Sso.provider_for).
  class SsoProvider < Loam::TenantRecord
    self.table_name = "loam_sso_providers"

    include Loam::Auditable      # config changes are audited; the secret is redacted
    include Loam::Encryptable

    # Tenant-scoped key (default): SSO config belongs to the tenant, and the
    # secret is only ever read inside that tenant's context on callback.
    encrypts :client_secret

    has_many :identities, class_name: "Loam::SsoIdentity",
             foreign_key: :sso_provider_id, dependent: :delete_all

    validates :name, :protocol, :domain, :jit_role, presence: true
    # Globally unique so HRD resolves exactly one owning IdP per domain. Rails'
    # uniqueness validator queries WITHOUT the default tenant scope, so this
    # catches a collision across tenants too.
    validates :domain, uniqueness: true

    normalizes :domain, with: ->(domain) { domain.to_s.strip.downcase.presence }

    scope :active, -> { where(active: true) }

    # IdP group -> Loam role, first match wins; falls back to jit_role.
    def group_roles
      group_role_map.is_a?(Hash) ? group_role_map : {}
    end
  end
end
