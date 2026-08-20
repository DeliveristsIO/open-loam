# Loam — architecture

Loam is an **opinionated foundation, delivered as one Rails engine gem.** Each
pillar is a small, self-contained implementation living under `Loam::`; the
value is the *fusion* — that they all agree with each other and with the
tenancy boundary on day zero — and the *agent-legibility layer* on top.

> **Prototype note (2026-08).** The original plan was to *wrap* proven gems
> (`acts_as_tenant`, `pundit`, `paper_trail`, Rails Event Store, Avo). The
> prototype instead ships **minimal in-gem implementations** behind Loam's own
> conventions — the smallest surface that proves the conventions and the agent
> flow end to end. Swapping the proven gems back in *behind the same public
> conventions* is the roadmap (backlog L-201..L-204), not a reversal: the
> `Loam::` API is the contract, its internals are replaceable.

## Shape

Loam ships as a single Rails **engine** + generators + an `AGENTS.md`
contract, layered over a standard Rails 8 app.

```
app/                     your business (the 20%)
lib/loam/                the foundation (the 80%)
  tenant_record.rb       tenant model base class + default-scope isolation
  current.rb             per-request tenant/actor context
  policy.rb              roles + field-level write rules
  auditable.rb           change tracking, on by default
  events.rb / eventful.rb  domain event bus + lifecycle events
  custom_fields.rb       runtime fields (Loam::FieldDefinition + json column)
  workflow.rb            states, transitions, role-gated approvals
  notifications.rb       tenant-scoped in-app notifications
  webhooks.rb            per-tenant signed outbound delivery
  commentable.rb / attachable.rb   comments + ActiveStorage attachments
  searchable.rb          declared search + index filtering
  lifecycle.rb           on_tenant_created hooks + loam:sync
app/models/loam/         engine models (Tenant, Membership, AuditRecord,
                         FieldDefinition, Notification, ApiToken, WebhookEndpoint, Comment)
lib/generators/loam/     install + entity generators (the one interface)
AGENTS.md                agent conventions + guardrails (byte-budgeted)
```

## Pillars → how they're built

| Pillar | Prototype implementation | Roadmap target |
|--------|--------------------------|----------------|
| **Multi-tenancy** | `Loam::TenantRecord` with a `default_scope` on `Loam::Current.tenant`; a missing tenant **raises** `MissingTenantError` rather than widening the query. Row-level, `tenant_id` on every scoped table. | evaluate `acts_as_tenant` behind the same base class (L-201) |
| **Authorization** | `Loam::Policy` — a policy class per entity, role from `Loam::Membership`, field-level `writable:` rules enforced in the controller permit list. | wrap `pundit`'s policy objects (L-202) |
| **Custom fields** | A `custom_fields` **json** column + runtime `Loam::FieldDefinition` rows; typed read/write, admin-managed, no migration. | a read-model index for filter/sort at scale (L-703); Postgres `jsonb`/GIN in production |
| **Event backbone** | `Loam::Events` over `ActiveSupport::Notifications`; `domain.thing.happened` naming, tenant/actor stamped on every payload. | wrap Rails Event Store; formal ephemeral/persistent subscriber contract (L-204, L-706) |
| **Workflow** | `Loam::Workflow` DSL — states with inclusion validation, transitions with `from`/`to`/`roles`, generated bang methods, transition events. | undo/redo command layer (L-704) |
| **Audit** | `Loam::Auditable` — `after_commit` writes a tenant- and actor-tagged `Loam::AuditRecord` with the changeset. | wrap `paper_trail` (L-203) |
| **Soft-delete** | `Loam::SoftDeletable` — a `deleted_at` column and a second `default_scope` that composes with tenancy; deleted rows are excluded by default, `with_deleted` lifts only the `deleted_at` filter (never tenancy), and `soft_delete`/`restore` reuse the audit path. | wrap `discard`/`paranoia` behind the same concern (L-902) |
| **Notifications / API / webhooks** | `Loam::Notifications`, a token-auth JSON API per entity, `Loam::Webhooks` with HMAC-signed ActiveJob delivery. | — |
| **Admin** | Generated Hotwire-free ERB console: CRUD, comments, attachments, global search, filtering, pagination, permission-aware. | evaluate Avo as an alternate backend (L-403) |
| **Background** | ActiveJob (webhook delivery, digests); tenant context carried explicitly in jobs via `Loam.as_tenant`. | Solid Queue defaults |

Nothing here is exotic — that's the point. A new project gets all of it
**wired together and agreeing with each other** on day zero.

## Agent-legibility layer

What makes Loam *agent-native* rather than just a starter kit:

1. **`AGENTS.md`** — the canonical map: where entities/policies/events/screens
   live, the one way to add each, and the invariants an agent must not break
   (tenancy, authorization). Byte-budgeted (≤32 KB, enforced by a guardrail
   test) so an agent harness never silently truncates its tail.
2. **Generators as the interface** — agents add features by invoking Loam
   generators (`rails g loam:entity Subscription ...`), not free-form file
   creation. Output is predictable and reviewable.
3. **Structural guardrails** — tenancy and authorization are enforced by base
   classes and default scopes, so an agent *can't* silently produce a
   cross-tenant leak or an unauthorized action; it shows up as a failing test.
   A lint fails on any non-scoped business model or any `.unscoped` in `app/`.
4. **Measured** — a golden-tasks benchmark (`ai/`) runs agents against fresh
   apps and audits the result. First run: 10/10 tasks, zero isolation or
   authorization violations, versus 1/10 isolation on a vanilla-Rails control.
5. **Spec-first flow** *(roadmap, L-708)* — an agent writes a short spec,
   generates scaffolding, fills the business logic, conventions keep it inside
   the lines.

## Example: what "add a feature" looks like

> "Add a `Subscription` entity: fields plan, status, renews_at; tenant-scoped;
> admin screen; only Billing role can edit; emit `billing.subscription.renewed`."

An agent (or human) runs the entity generator, declares the policy rule, adds
the workflow/event, and the admin panel comes with it — each a conventional,
audited, tenant-scoped step. No decisions about *how* tenancy or permissions
work, because Loam already decided. This is exactly the shape the benchmark
exercises.

## Non-goals

- Not a commerce product (that's Spree/Solidus) — Loam is domain-agnostic.
- Not a low-code builder — it produces normal, readable Rails code.
- Not a fork of Rails — it's an engine + conventions on top of stock Rails.

## Decisions made in the prototype

The original open questions, now resolved (revisit if real usage argues otherwise):

- **Tenancy strategy** → row-level (`tenant_id` + `default_scope`), missing
  context raises. Not schema-per-tenant.
- **Custom-fields engine** → json column + `FieldDefinition` typed accessors,
  not full EAV. Portable `json` today (SQLite demo); `jsonb`/GIN in production;
  a read-model index is the scaling path (L-703).
- **Admin** → a generated ERB console (control over a dependency) for now; Avo
  left as an evaluated alternative (L-403).
- **Agent pack** → a Loam-specific `AGENTS.md` contract, byte-budgeted, with a
  golden-tasks benchmark rather than a reused third-party convention set.
