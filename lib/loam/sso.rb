require "loam/sso/claims"
require "loam/sso/http_client"
require "loam/sso/oidc_provider"
require "loam/sso/fake_provider"

module Loam
  # Single sign-on. SHIPPED: OIDC Authorization Code flow end-to-end —
  # home-realm discovery by email domain, just-in-time user provisioning, IdP
  # group -> role mapping, and account linking to an existing User. SEAMS
  # (documented, not built): SAML (another protocol behind the same interface,
  # raises NotImplementedError until implemented) and SCIM 2.0 provisioning
  # (see docs/architecture.md). See Loam::SsoProvider for the per-tenant config.
  #
  # A protocol provider implements two methods:
  #   authorization_url(state:, login_hint: nil) -> the IdP URL to redirect to
  #   exchange(code:)                             -> Loam::Sso::Claims
  #
  # The provider is built through a swappable `builder` so tests and the demo
  # inject a FakeProvider and NOTHING touches the network. Loam::Sso::OidcProvider
  # is the real one; it is never constructed in the test suite.
  module Sso
    class Error < Loam::Error; end

    # The identity provider did not assert a verified email. Linking or creating
    # an account on an unverified email is an account-takeover vector, so the
    # flow refuses it.
    class UnverifiedEmailError < Error; end

    class << self
      attr_writer :builder

      def builder
        @builder ||= method(:default_builder)
      end

      # Wrap a Loam::SsoProvider record in its protocol provider.
      def build(record, redirect_uri:)
        builder.call(record, redirect_uri)
      end

      def default_builder(record, redirect_uri)
        case record.protocol
        when "oidc"
          OidcProvider.new(record, redirect_uri: redirect_uri)
        when "saml"
          raise NotImplementedError,
                "SAML SSO is a documented seam — implement Loam::Sso::SamlProvider behind this interface."
        else
          raise Error, "Unsupported SSO protocol: #{record.protocol.inspect}"
        end
      end

      # Home-realm discovery. THE blessed cross-tenant lookup for SSO (like
      # Loam::Membership.tenants_for): "which tenant's IdP owns this email
      # domain?" is asked at the sign-in page, before any tenant is chosen, so it
      # reaches across tenants via `unscoped` — something host code must never do.
      def provider_for(email:)
        domain = email.to_s.split("@").last.to_s.strip.downcase
        return nil if domain.blank?

        Loam::SsoProvider.unscoped.where(domain: domain, active: true).first
      end

      # Resolve verified IdP claims to a signed-in User, in the provider's tenant.
      # MUST be called inside Loam.as_tenant(provider.tenant). Order matters:
      # match the durable (provider, sub) identity first, then an existing User by
      # verified email (link), else just-in-time create — always with a tenant
      # membership at the mapped role.
      def provision(provider, claims)
        raise UnverifiedEmailError, "the identity provider did not verify #{claims.email.inspect}" unless claims.email_verified?

        identity = Loam::SsoIdentity.find_by(sso_provider_id: provider.id, sub: claims.sub)
        return identity.user if identity

        user = User.find_by(email: claims.email) || jit_create_user(claims)
        ensure_membership(provider, user, claims)
        Loam::SsoIdentity.create!(user: user, sso_provider: provider, sub: claims.sub)
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

      def ensure_membership(provider, user, claims)
        Loam::Membership.find_or_create_by!(user_id: user.id) do |membership|
          membership.role = role_for(provider, claims)
        end
      end
    end
  end
end
