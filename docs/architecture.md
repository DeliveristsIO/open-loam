# Loam — architecture

Loam is an **assembly, not an invention.** Each pillar has a battle-tested Rails
foundation; Loam's contribution is the *fusion*, the opinionated conventions on
top, and the agent-legibility layer. This keeps the surface small and the risk
low — we integrate proven components rather than rebuild them.

## Shape

Loam ships as a set of Rails **engines** + generators + an agent pack, layered
over a standard Rails 8 app (PostgreSQL, Solid Queue/Cable, Hotwire).

```
app/            your business (the 20%)
loam/           the engines (the 80%)
  tenancy/      tenant model, scoping, resolution
  authz/        roles, policies, field-level access
  entities/     custom-entity + custom-field engine
  events/       domain event bus, subscribers, projections
  audit/        change tracking
  admin/        generated internal console
AGENTS.md       agent conventions + guardrails
.loam/agents/   opencode/Claude/Codex agent pack
```

## Pillars → proven foundations

| Pillar | Built on | Loam adds |
|--------|----------|-----------|
| **Multi-tenancy** | `acts_as_tenant` (or a Loam current-tenant middleware) | Default tenant-scoping on generated models, jobs, and events; a tenant resolver (subdomain/header/session); tests that fail if a model isn't scoped. |
| **Authorization** | `pundit` (policy objects) | A role model + policy generators; field-level visibility; a convention that every action has a policy. |
| **Custom entities** | PostgreSQL columns + JSONB with GIN indexing (the pattern Spree metafields uses) | A runtime entity/field definition API, migration-free custom fields, and typed accessors so agents/admins extend the model safely. |
| **Event backbone** | [Rails Event Store](https://railseventstore.org) | Naming conventions (`domain.thing.happened`), generators for events/subscribers, and projections wired into the admin. |
| **Audit** | `audited` / `paper_trail` | Tenant- and actor-tagged change records, on by default, surfaced in admin. |
| **Admin** | `avo` (or a generated Hotwire console) | Auto-registration of Loam entities, permission-aware, extended per model by convention. |
| **Background / realtime** | Solid Queue + Solid Cable | Tenant-aware job base class; broadcasts scoped to tenant. |

Nothing here is exotic — that's the point. The value is that a new project gets
all of it **wired together and agreeing with each other** on day zero.

## Agent-legibility layer

What makes Loam *agent-native* rather than just a starter kit:

1. **`AGENTS.md`** — the canonical map: where entities/policies/events/screens
   live, the one way to add each, and the invariants an agent must not break
   (tenancy, authorization).
2. **Generators as the interface** — agents add features by invoking Loam
   generators (`rails g loam:entity Subscription ...`), not free-form file
   creation. Output is predictable and reviewable.
3. **Structural guardrails** — tenancy and authorization are enforced by base
   classes and default scopes, so an agent *can't* silently produce a
   cross-tenant leak or an unauthorized action; it shows up as a failing test.
4. **Live legibility (MCP)** — optional MCP tools exposing the current schema,
   entities, routes, and policies so an agent reasons about the *actual* app.
5. **Spec-first flow** — an agent writes a short spec, generates scaffolding,
   fills the business logic, and the conventions keep it inside the lines.

## Example: what "add a feature" looks like

> "Add a `Subscription` entity: fields plan, status, renews_at; tenant-scoped;
> admin screen; only Billing role can edit; emit `billing.subscription.renewed`."

An agent (or human) runs the entity generator, adds the policy, declares the
event and a subscriber, and registers the admin panel — each a conventional,
audited, tenant-scoped step. No decisions about *how* tenancy or permissions
work, because Loam already decided.

## Non-goals

- Not a commerce product (that's Spree/Solidus) — Loam is domain-agnostic.
- Not a low-code builder — it produces normal, readable Rails code.
- Not a fork of Rails — it's engines + conventions on top of stock Rails.

## Open questions to resolve in the prototype

- Tenancy strategy: row-level (`acts_as_tenant`) vs schema-per-tenant — pick one
  opinionated default.
- Custom-entity engine: how far toward EAV vs JSONB-with-typed-accessors.
- Admin: adopt Avo vs generate a Hotwire console (dependency vs control).
- Agent pack: reuse `rails_ai_agents` conventions vs a Loam-specific set.
