module Loam
  module Sso
    # Normalized identity claims, protocol-independent. Every provider's
    # `exchange` returns one of these so the rest of the flow never knows whether
    # it came from OIDC, SAML, or a test fake.
    Claims = Data.define(:sub, :email, :email_verified, :name, :groups) do
      def email_verified? = email_verified == true || email_verified.to_s == "true"
    end
  end
end
