---
title: Single Sign-On (SSO)
description: "Per-tenant OIDC single sign-on: home-realm discovery, JIT provisioning, and IdP group-to-role mapping."
nav_order: 5
---

# Single sign-on (SSO)


A tenant connects its own OIDC provider at `/admin/sso_providers` (issuer,
client_id, client_secret, email `domain`, JIT role). Home-realm discovery routes
a user to their IdP by email domain; on callback a VERIFIED identity is
provisioned just-in-time (or linked to an existing User by verified email — an
UNVERIFIED email is refused, never linked, so there is no account takeover) with
a tenant membership at the mapped role. The client_secret is encrypted at rest,
so `OPEN_LOAM_MASTER_KEY` must be set. OIDC is shipped end-to-end; SAML and SCIM are
seams behind the protocol interface. In tests, inject `OpenLoam::Sso::FakeProvider`
via `OpenLoam::Sso.builder` so nothing touches the network.

## Domain ownership is confirmed off the admin path

The `domain` is typed by a tenant manager, so on its own it proves nothing. A
provider does nothing until an **operator** confirms ownership:

```
bin/rails open_loam:sso:providers                 # list providers and their state
bin/rails open_loam:sso:verify_domain[42]         # stamp domain_verified_at
bin/rails open_loam:sso:unverify_domain[42]
```

Until then, home-realm discovery skips the provider, and `OpenLoam::Sso.provision`
raises `UnverifiedDomainError` rather than linking an account that already
exists. JIT-creating a NEW user still works — that user lands in the claiming
tenant and touches nothing outside it. Editing `domain` clears the confirmation,
so an approved provider cannot be repointed at a domain nobody approved.

`domain_verified_at` is deliberately absent from the admin form's permitted
params: the manager making the claim is the party the check constrains. Confirm
ownership out of band (DNS TXT, a signed request from the domain's operator, an
existing contract) before running the task.

