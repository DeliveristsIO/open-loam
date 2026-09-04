---
title: Guardrails
description: How OpenLoam turns its invariants into failing tests instead of prose an agent can skim past.
nav_order: 2
permalink: /agents/guardrails/
---

# Guardrails

## Documentation versus enforcement

`AGENTS.md` *tells* an agent the rules. Guardrails *enforce* them — as tests
that fail the moment code violates an invariant, whether or not whoever wrote
the code read the docs first.

```text
agent writes implementation
        ↓
guardrail test runs (bin/rails test)
        ↓
structural violation? ──yes──> test fails, agent sees exactly what broke
        │no
        ↓
suite green — the invariant held
```

This is what makes OpenLoam *agent-native* rather than just well-documented: a
model that skips `OpenLoam::TenantRecord`, or a stray `.unscoped`, doesn't need a
human reviewer to catch it in code review. It fails in CI, with a message
that names the offending file.

## Repo-wide guardrails

Installed once by `open_loam:install` at `test/open_loam_guardrails_test.rb`, and
apply to the whole app — not per-entity.

### Every business model is tenant-scoped

**Protects:** the [tenant-isolation]({% link _foundation/tenant-isolation.md %})
guarantee at the model-class level, not just per-query.
**Triggers on:** any `ActiveRecord::Base` descendant that is not abstract,
not framework plumbing (`ActiveStorage::`, `ActionText::`, `ActionMailbox::`,
`SolidQueue::`, `SolidCache::`, `SolidCable::`), not on the explicit
allowlist (`ApplicationRecord`, `User`, `OpenLoam::Tenant`, `OpenLoam::Config`,
`OpenLoam::MfaCredential`, `OpenLoam::AuthAttempt`), and does not inherit
`OpenLoam::TenantRecord`.
**Example failure:**
```text
These models are NOT tenant-scoped: Invoice.
Business models must inherit OpenLoam::TenantRecord (use `rails g open_loam:entity`).
```
**Fix:** generate the model with `open_loam:entity`, or change its superclass to
`OpenLoam::TenantRecord`. If it's intentionally global, add it to
`TENANCY_ALLOWLIST` in the guardrail test itself — in review, on purpose,
not by accident.

### Touching a tenant-scoped model with no context raises

**Protects:** the fail-loud behavior tenant isolation depends on.
**Triggers on:** any query against a tenant-scoped model with
`OpenLoam::Current.tenant` unset.
**Example failure:** the test asserts `OpenLoam::MissingTenantError` is raised —
if a future change made a query silently return `[]` or all rows instead,
this test would fail (a green suite here is what proves the failure mode
still fails loudly).
**Fix:** n/a — this guardrail should always pass; if it doesn't, something
weakened `TenantRecord`'s `default_scope` or `before_save` check.

### No `.unscoped` outside vetted framework code

**Protects:** against the one line of code that bypasses tenant isolation
entirely.
**Triggers on:** any file under `app/**/*.rb` matching `\bunscoped\b`.
**Example failure:**
```text
.unscoped found in: app/models/report.rb. It bypasses tenant isolation — remove it.
```
**Fix:** don't reach for `.unscoped`. If cross-tenant access is genuinely
needed (rare — token auth, SSO discovery, the scheduler tick), that logic
belongs in the gem, not the host app; see
[Tenant isolation → safe system-level access]({% link _foundation/tenant-isolation.md %}#safe-system-level-access).

### `AGENTS.md` stays inside its byte budget

**Protects:** against silent truncation by agent harnesses that read
instruction files into a fixed context window.
**Triggers on:** `AGENTS.md` exceeding 32,768 bytes.
**Fix:** cut prose or move detail into `docs/` and link it — never raise the
budget. See [The agent contract]({% link _agents/agent-contract.md %}).

### Every `FieldDefinition.entity_type` resolves correctly

**Protects:** against a typo'd custom-field entity type silently pointing at
nothing.
**Triggers on:** a `OpenLoam::FieldDefinition` row whose `entity_type` doesn't
resolve to a real class that `include`s `OpenLoam::CustomFields`.
**Fix:** fix the typo, or make sure the target model includes
`OpenLoam::CustomFields` (every generated entity does by default).

## Per-entity guardrails

`open_loam:entity` generates `test/entities/<name>_test.rb` from
[a template](https://github.com/DeliveristsIO/open-loam/blob/main/lib/generators/open_loam/entity/templates/entity_test.rb)
that proves the invariants hold for *that specific entity*, not just in the
abstract:

- **Records are invisible outside their tenant** — creating in tenant A and
  querying from tenant B returns zero, and `find` by id raises
  `ActiveRecord::RecordNotFound`.
- **Touching the model with no tenant context raises** `OpenLoam::MissingTenantError`.
- **A record cannot be written into a foreign tenant** — updating a
  tenant-A record while tenant B is current raises `OpenLoam::MissingTenantError`
  (from `TenantRecord`'s `before_save` check).
- **Every change is audited** with the correct actor and changeset key.
- **Lifecycle events are published with the tenant stamped** on the payload.
- **Soft-delete hides a record by default, stays tenant-scoped, and
  restores** — including the specific check that `with_deleted` lifts the
  `deleted_at` filter but never the tenant filter.
- **Policy denies a non-member** — a user with no membership in the record's
  tenant fails both `update?` and `writable?` on every field.

The comment at the top of the generated file is explicit about the intent:
*"Extend freely; never delete."* Deleting a generated test to make a change
pass is exactly the shortcut this system exists to make visible.

## Related pages

- [Tenant isolation]({% link _foundation/tenant-isolation.md %})
- [Authorization]({% link _foundation/authorization.md %})
- [The agent contract]({% link _agents/agent-contract.md %})
- [Golden tasks]({% link _agents/golden-tasks.md %}) — guardrail-failure rate
  is one of the tracked metrics.
