# 0001. Row-level tenancy

- Status: Accepted
- Date: 2026-08

## Context
Every model in a business app must be isolated per tenant. The two options are
schema-per-tenant (a Postgres schema or database each) and row-level (`tenant_id`
+ a scope). Schema-per-tenant isolates hard but multiplies migration and
connection complexity and fights a shared admin/agent surface.

## Decision
Row-level: `Loam::TenantRecord` applies a `default_scope` on `Loam::Current.tenant`;
every scoped table carries `tenant_id`; a query with no tenant context **raises**
`MissingTenantError` rather than silently widening.

## Consequences
- One schema, one connection, ordinary migrations — an agent adds a model without
  touching tenancy plumbing.
- Isolation is structural: a missing context is a loud failure caught by a test,
  and a guardrail lint bans `.unscoped` in `app/`.
- Cross-tenant reads that genuinely need to bypass the scope (token auth, home-realm
  discovery) are a short, blessed, gem-only list — never host-app code.
- Revisit if a tenant needs physical data separation for compliance; a
  business-facing `Organization` layer can still sit on top without renaming the core.
