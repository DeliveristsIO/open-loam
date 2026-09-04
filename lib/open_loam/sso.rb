require "open_loam/sso/claims"
require "open_loam/sso/http_client"
require "open_loam/sso/oidc_provider"
require "open_loam/sso/fake_provider"

module OpenLoam
  # Single sign-on. SHIPPED: OIDC Authorization Code flow end-to-end —
  # home-realm discovery by email domain, just-in-time user provisioning, IdP
  # group -> role mapping, and account linking to an existing User. SEAMS
  # (documented, not built): SAML (another protocol behind the same interface,
  # raises NotImplementedError until implemented) and SCIM 2.0 provisioning
  # (see docs/_foundation/overview.md). See OpenLoam::SsoProvider for the per-tenant config.
  #
  # A protocol provider implements two methods:
  #   authorization_url(state:, login_hint: nil) -> the IdP URL to redirect to
  #   exchange(code:)                             -> OpenLoam::Sso::Claims
  #
  # The provider is built through a swappable `builder` so tests and the demo
  # inject a FakeProvider and NOTHING touches the network. OpenLoam::Sso::OidcProvider
  # is the real one; it is never constructed in the test suite.
  module Sso
    class Error < OpenLoam::Error; end

    # The identity provider did not assert a verified email. Linking or creating
    # an account on an unverified email is an account-takeover vector, so the
    # flow refuses it.
    class UnverifiedEmailError < Error; end

    # The verified email is on a domain this provider does not own. A provider
    # only vouches for its OWN domain; letting it assert an email on another
    # domain would let a tenant's IdP hijack a user of a different domain
    # (cross-domain account takeover), so the flow refuses it.
    class DomainMismatchError < Error; end

    class << self
      attr_writer :builder

      def builder
        @builder ||= method(:default_builder)
      end

      # Wrap a OpenLoam::SsoProvider record in its protocol provider.
      def build(record, redirect_uri:)
        builder.call(record, redirect_uri)
      end

      def default_builder(record, redirect_uri)
        case record.protocol
        when "oidc"
          OidcProvider.new(record, redirect_uri: redirect_uri)
        when "saml"
          raise NotImplementedError,
                "SAML SSO is a documented seam — implement OpenLoam::Sso::SamlProvider behind this interface."
        else
          raise Error, "Unsupported SSO protocol: #{record.protocol.inspect}"
        end
      end

      # Home-realm discovery. THE blessed cross-tenant lookup for SSO (like
      # OpenLoam::Membership.tenants_for): "which tenant's IdP owns this email
      # domain?" is asked at the sign-in page, before any tenant is chosen, so it
      # reaches across tenants via `unscoped` — something host code must never do.
      def provider_for(email:)
        domain = email.to_s.split("@").last.to_s.strip.downcase
        return nil if domain.blank?

        OpenLoam::SsoProvider.unscoped.where(domain: domain, active: true).first
      end

      # Resolve verified IdP claims to a signed-in User, in the provider's tenant.
      # MUST be called inside OpenLoam.as_tenant(provider.tenant). Order matters:
      # match the durable (provider, sub) identity first, then an existing User by
      # verified email (link), else just-in-time create — always with a tenant
      # membership at the mapped role.
      def provision(provider, claims)
        raise UnverifiedEmailError, "the identity provider did not verify #{claims.email.inspect}" unless claims.email_verified?

        # The provider only vouches for its own domain. Check this BEFORE any
        # lookup, link, or create — an email on another domain is refused
        # outright (no session, nothing touched).
        email_domain = claims.email.to_s.split("@").last.to_s.downcase
        unless email_domain.present? && email_domain == provider.domain.to_s.downcase
          raise DomainMismatchError,
                "verified email domain #{email_domain.inspect} is not this provider's domain #{provider.domain.inspect}"
        end

        # Resolve the user: the durable (provider, sub) identity first, then an
        # existing User by verified email (link), else just-in-time create.
        identity = OpenLoam::SsoIdentity.find_by(sso_provider_id: provider.id, sub: claims.sub)
        user = identity&.user || User.find_by(email: claims.email) || jit_create_user(claims)

        # Re-map claims -> role on EVERY login (including a returning identity),
        # so an IdP role change takes effect.
        ensure_membership(provider, user, claims)
        OpenLoam::SsoIdentity.create!(user: user, sso_provider: provider, sub: claims.sub) unless identity
        user
      end

      # IdP group -> role; first configured group that the user carries wins,
      # otherwise the provider's default role.
      def role_for(provider, claims)
        map = provider.group_roles
        match = Array(claims.groups).map(&:to_s).find { |group| map.key?(group) }
        match ? map[match] : provider.jit_role
      end

      private

      def jit_create_user(claims)
        # SSO users authenticate at the IdP; the random password satisfies
        # has_secure_password and is unguessable, never used to log in.
        User.create!(
          name: claims.name.presence || claims.email,
          email: claims.email,
          password: SecureRandom.hex(32)
        )
      end

      # Re-map claims -> role on EVERY login, so an IdP role change takes effect
      # (a promotion reflects, a removed group downgrades) rather than freezing
      # at whatever the role was when the membership was first created.
      def ensure_membership(provider, user, claims)
        membership = OpenLoam::Membership.find_or_initialize_by(user_id: user.id)
        membership.role = role_for(provider, claims)
        membership.save!
      end
    end
  end
end
