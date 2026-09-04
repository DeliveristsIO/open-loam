module OpenLoam
  module Sso
    # The real OIDC Authorization Code provider. Discovers the issuer's endpoints
    # from its .well-known document, sends the user to the authorization endpoint,
    # then exchanges the returned code for an access token and reads the claims
    # from the userinfo endpoint.
    #
    # Why userinfo rather than validating the id_token's JWT signature: these
    # claims arrive over a server-to-server TLS channel WE opened, authenticated
    # by the client_secret — the browser never touches them. Signature validation
    # exists for a token you RECEIVE (the id_token, relayed via the browser);
    # fetching userinfo over an authenticated back channel sidesteps hand-rolled
    # JWKS verification for the prototype. Roadmap: full id_token + JWKS.
    #
    # NOT exercised by the test suite (a FakeProvider is injected via
    # OpenLoam::Sso.builder); live OIDC against a real IdP is verified manually.
    class OidcProvider
      SCOPE = "openid email profile".freeze

      def initialize(record, redirect_uri:)
        @record = record
        @redirect_uri = redirect_uri
      end

      def authorization_url(state:, login_hint: nil)
        params = {
          response_type: "code",
          client_id: @record.client_id,
          redirect_uri: @redirect_uri,
          scope: SCOPE,
          state: state
        }
        params[:login_hint] = login_hint if login_hint.present?
        "#{discovery.fetch('authorization_endpoint')}?#{params.to_query}"
      end

      def exchange(code:)
        token = HttpClient.post_form(discovery.fetch("token_endpoint"), {
          grant_type: "authorization_code",
          code: code,
          redirect_uri: @redirect_uri,
          client_id: @record.client_id,
          client_secret: @record.client_secret
        })

        info = HttpClient.get_json(discovery.fetch("userinfo_endpoint"), bearer: token.fetch("access_token"))

        Claims.new(
          sub: info["sub"],
          email: info["email"],
          email_verified: info["email_verified"],
          name: info["name"],
          groups: Array(info["groups"])
        )
      end

      private

      def discovery
        @discovery ||= HttpClient.get_json(File.join(@record.issuer, ".well-known/openid-configuration"))
      end
    end
  end
end
