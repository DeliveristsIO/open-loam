---
title: Tenant isolation
description: How Loam makes cross-tenant data leaks structurally impossible instead of a convention to remember.
nav_order: 2
permalink: /foundation/tenant-isolation/
---

# Tenant isolation

## Concept

A tenant is a `Loam::Tenant` row — one customer/organization/account in a
multi-tenant Loam app. Every business record belongs to exactly one tenant,
and every business model is tenant-*owned*: it inherits `Loam::TenantRecord`
(`lib/loam/tenant_record.rb`), which puts a `default_scope` on
`Loam::Current.tenant` onto every query, assigns the current tenant
automatically on create, and validates `tenant_id` presence.

Isolation is **row-level**, not schema-per-tenant: one database, one
connection, `tenant_id` on every scoped table. The tradeoff and the
alternative considered are in [ADR 0001]({% link _adr/0001-row-level-tenancy.md %}).

## Example

```ruby
class Equipment < Loam::TenantRecord
  include Loam::Auditable
  include Loam::Eventful
end

Loam.as_tenant(acme) do
  Equipment.create!(name: "Excavator")
  Equipment.count   # => 1 — scoped to acme
end

Loam.as_tenant(globex) do
  Equipment.count   # => 0 — a different tenant, a different world
end
```

`Loam.as_tenant(tenant, actor: nil) { }` (`lib/loam.rb`) is **the one blessed
way** to establish or switch tenant context — it sets `Loam::Current.tenant`
(and `actor`, if given), yields, and restores the previous context afterward,
even on exception. A controller sets it once per request (typically from the
signed-in user's chosen membership); a background job sets it explicitly,
since there's no request to inherit it from.

## Failure mode

Touch a tenant-scoped model with **no** tenant in context, and it raises
immediately — it does not return an empty relation, and it does not widen to
every tenant's rows:

```ruby
Loam::Current.reset
Equipment.count
# => Loam::MissingTenantError:
#    No tenant set in Loam::Current — wrap this call in Loam.as_tenant(tenant) { ... }
```

That's `Loam.tenant!` (`lib/loam.rb`) under the hood — `Current.tenant or raise
MissingTenantError` — which every tenant-scoped code path calls. There is no
silent fallback. A write path fails the same way: `TenantRecord`'s `before_save`
callback checks `tenant_id != Loam.tenant!.id` and raises `MissingTenantError`
again if a record is ever about to be saved into a foreign tenant.

**Background jobs** don't get a request to inherit tenant context from, so a
job body must wrap its work in `Loam.as_tenant(tenant, actor:)` explicitly —
omitting it doesn't leak, it just raises the moment the job touches a
tenant-scoped model, which surfaces the bug in a job-failure alert instead of
a cross-tenant read.

## Safe system-level access

`Model.unscoped` is the escape hatch — deliberately the standard Rails
spelling, so it's trivially greppable in review. It is reserved for a short,
named list of vetted gem-internal call sites that have a real cross-tenant
reason to exist (documented in `lib/loam/tenant_record.rb` and the guardrail
test below): token authentication, SSO home-realm discovery by email domain,
and the scheduler's tick runner (which has no tenant of its own — it scans
across tenants to find due jobs). Host-app code never needs it: business logic
runs inside `Loam.as_tenant`.

## Prohibited bypasses

- **Never call `.unscoped` on a tenant-scoped model from app code.** The
  guardrail test `test/loam_guardrails_test.rb` (installed by `loam:install`)
  greps `app/**/*.rb` for `\bunscoped\b` and fails the build if it finds one
  outside the gem's own vetted call sites.
- **Never rescue `Loam::MissingTenantError`.** It firing means a bug upstream
  — a missing `Loam.as_tenant` wrapper — not a condition to handle gracefully.
  [AGENTS.md](https://github.com/DeliveristsIO/open-loam/blob/main/lib/generators/loam/install/templates/AGENTS.md)
  states this as an invariant an agent must not break.
- **Every business model must inherit `Loam::TenantRecord`.** The same
  guardrail test eager-loads the app and asserts every `ActiveRecord::Base`
  descendant is either abstract, framework plumbing (ActiveStorage,
  ActionText, …), on a short explicit allowlist (`Loam::Config`,
  `Loam::MfaCredential`, `User` — things that are legitimately global or
  cross-tenant by design), or `<= Loam::TenantRecord`.

## Why Loam behaves this way

A missing tenant context is the single most dangerous failure mode in a
multi-tenant app — silently widening a query means one tenant's data leaks
into another's page, API response, or export. Loam's structural answer: make
that failure loud and immediate (a raised exception, caught by a test) rather
than quiet and gradual (a query that happens to work in dev because there's
only one tenant, and leaks in production because there's two). See
[ADR 0001]({% link _adr/0001-row-level-tenancy.md %}) for the full reasoning
and the schema-per-tenant alternative it rejects.

This is also the property an [internal benchmark]({% link _agents/golden-tasks.md %})
measured directly: across ten AI-agent-implemented tasks, tenant isolation
held on all ten Loam apps and on one of ten hand-rolled vanilla-Rails apps
given the identical prompts. (Same model family built both sides — see the
benchmark page for the full caveats.)

## Agent guidance

- Business models: `class Thing < Loam::TenantRecord`, never `ApplicationRecord`.
- Don't write raw SQL against a tenant table without a `tenant_id` predicate.
- In a background job, wrap tenant-scoped work in `Loam.as_tenant(tenant, actor:)`
  — there's no request to inherit context from.
- If a guardrail test fails on `.unscoped` or a non-`TenantRecord` model, that
  is the intended outcome of stepping outside the convention — fix the model,
  don't loosen the test.
- In tests, `with_tenant(tenant, actor:) { }` (from `Loam::TestHelpers`, wired
  in by `loam:install`) is the test-suite equivalent of `Loam.as_tenant`.

## Related pages

- [Authorization]({% link _foundation/authorization.md %}) — a different
  question: not *whose* data, but *who* may act on it.
- [Guardrails]({% link _agents/guardrails.md %}) — how these invariants are
  enforced as tests, not just documentation.
- [ADR 0001: Row-level tenancy]({% link _adr/0001-row-level-tenancy.md %})
- [Golden tasks]({% link _agents/golden-tasks.md %}) — the measured result.
