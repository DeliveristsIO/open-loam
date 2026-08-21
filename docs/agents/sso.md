# Single sign-on (SSO)


A tenant connects its own OIDC provider at `/admin/sso_providers` (issuer,
client_id, client_secret, email `domain`, JIT role). Home-realm discovery routes
a user to their IdP by email domain; on callback a VERIFIED identity is
provisioned just-in-time (or linked to an existing User by verified email — an
UNVERIFIED email is refused, never linked, so there is no account takeover) with
a tenant membership at the mapped role. The client_secret is encrypted at rest,
so `LOAM_MASTER_KEY` must be set. OIDC is shipped end-to-end; SAML and SCIM are
seams behind the protocol interface. In tests, inject `Loam::Sso::FakeProvider`
via `Loam::Sso.builder` so nothing touches the network.

