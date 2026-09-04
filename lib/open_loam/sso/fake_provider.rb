require "base64"

module OpenLoam
  module Sso
    # An OFFLINE stand-in for a real IdP — for the demo and the test suite ONLY,
    # NEVER production. `authorization_url` loops straight back to our own
    # callback carrying the login email (as the "code"), so the whole SSO
    # round-trip runs with no network. `exchange` returns verified claims for
    # that email.
    #
    # Tests drive the security paths through two class-level overrides (reset in
    # teardown): `force_email_verified = false` to prove an unverified email is
    # refused, and `claims_override` to inject arbitrary claims (a fixed `sub`,
    # IdP groups for role mapping, a different email).
    class FakeProvider
      class << self
        attr_accessor :claims_override, :force_email_verified

        def reset!
          self.claims_override = nil
          self.force_email_verified = nil
        end
      end

      def initialize(record, redirect_uri:)
        @record = record
        @redirect_uri = redirect_uri
      end

      def authorization_url(state:, login_hint: nil)
        uri = URI(@redirect_uri)
        uri.query = { code: Base64.urlsafe_encode64(login_hint.to_s), state: state }.to_query
        uri.to_s
      end

      def exchange(code:)
        return self.class.claims_override if self.class.claims_override

        email = Base64.urlsafe_decode64(code.to_s)
        verified = self.class.force_email_verified.nil? ? true : self.class.force_email_verified
        Claims.new(
          sub: "fake|#{email}",
          email: email,
          email_verified: verified,
          name: email.split("@").first,
          groups: []
        )
      end
    end
  end
end
