module OpenLoam
  # A tenant's connection to an external identity provider (OIDC). Per-tenant
  # config: each tenant/org wires its OWN IdP, so the client_secret is encrypted
  # under the tenant key (the default Encryptable scope) — unlike MFA, which is
  # user-keyed. Home-realm discovery matches an email `domain` to the owning
  # provider at the sign-in page (see OpenLoam::Sso.provider_for).
  class SsoProvider < OpenLoam::TenantRecord
    self.table_name = "open_loam_sso_providers"

    include OpenLoam::Auditable      # config changes are audited; the secret is redacted
    include OpenLoam::Encryptable

    # Tenant-scoped key (default): SSO config belongs to the tenant, and the
    # secret is only ever read inside that tenant's context on callback.
    encrypts :client_secret

    has_many :identities, class_name: "OpenLoam::SsoIdentity",
             foreign_key: :sso_provider_id, dependent: :delete_all

    validates :name, :protocol, :domain, :jit_role, presence: true
    # Globally unique so HRD resolves exactly one owning IdP per domain. Rails'
    # uniqueness validator queries WITHOUT the default tenant scope, so this
    # catches a collision across tenants too.
    validates :domain, uniqueness: true

    normalizes :domain, with: ->(domain) { domain.to_s.strip.downcase.presence }

    # Editing the domain drops the proof — otherwise a verified provider could be
    # repointed at a domain nobody approved.
    before_validation :reset_domain_verification, if: -> { persisted? && domain_changed? }

    scope :active, -> { where(active: true) }
    scope :domain_verified, -> { where.not(domain_verified_at: nil) }

    # Until ownership is proven, HRD skips the provider and OpenLoam::Sso refuses
    # to link an existing account through it.
    def domain_verified? = domain_verified_at.present?

    # Operator entry point (rake open_loam:sso:verify_domain), off the admin path.
    def verify_domain!(at: Time.current)
      update!(domain_verified_at: at)
    end

    # IdP group -> OpenLoam role, first match wins; falls back to jit_role.
    def group_roles
      group_role_map.is_a?(Hash) ? group_role_map : {}
    end

    private

    def reset_domain_verification
      self.domain_verified_at = nil
    end
  end
end
