# Loam 🌱

**The fertile Rails foundation where AI agents grow business software.**

Loam is an opinionated, AI-native application foundation for Ruby on Rails.
Multi-tenancy, roles and permissions, an event backbone, custom entities, audit
trails, and an admin surface come **already decided** — as conventions, not
choices you re-litigate on every project. You bring the business; Loam is the
soil it grows in.

> Most app frameworks hand you a bag of seeds and an empty field. Loam hands you
> ground that's already rich — tenancy, permissions, events, auditing — so the
> first thing you plant is a *feature*, not plumbing.

---

## Why Loam exists

Every serious back-office app — CRM, ERP, ops console, internal tool — re-derives
the same ~80%: who's the tenant, who's allowed, what changed and when, how do
modules talk, where's the admin. Teams burn months on this before shipping a
single thing a customer cares about.

And now a second shift: **AI coding agents** (Claude Code, Codex, opencode) can
write real features — *if* the codebase is legible to them. Sprawling, snowflake
architectures confuse agents as much as they confuse new hires. Convention is
what makes a codebase safe for an agent to extend.

Loam fuses the two: **a pre-built business foundation that is deliberately
agent-legible.** Rails already leans convention-over-configuration — arguably the
most agent-friendly framework there is. Loam extends that philosophy from "how to
structure a controller" up to "how a multi-tenant, permissioned, audited business
domain is built" — and ships the agent conventions to match.

## The whitespace (why now)

This exact combination doesn't exist in Rails today. The pieces do — but scattered:

- **Foundation shape** (multi-tenant, RBAC, admin, audit) → Bullet Train, and the
  commerce products (Spree/Solidus).
- **Event backbone** → Rails Event Store.
- **AI-agent conventions** → `rails_ai_agents`, `rails/AGENTS.md`.
- **Custom entities / metadata modeling** → only inside commerce (Spree metafields).

**No Rails project unifies them.** The nearest *structural* analog — Frappe/ERPNext
(metadata-driven DocTypes, roles, workflows) — is **Python**. The TypeScript world
has [Open Mercato](https://github.com/open-mercato/open-mercato) staking this
claim. Rails, despite being an ideal substrate, has no one holding this ground.

Loam is that ground.

---

## What's already decided

Each pillar ships as a convention with sane defaults, overridable when you truly
need to — never a blank page.

| Pillar | What you get, out of the box |
|--------|------------------------------|
| 🏢 **Multi-tenancy** | Tenant isolation baked into every query, background job, and event. New models are tenant-scoped by default. |
| 🔐 **Permissions** | Roles, policies, and field-level access — declared, not hand-rolled per controller. |
| 🌾 **Custom entities** | Define domain objects and fields at runtime (hybrid columns + JSONB with real indexing), so agents and admins extend the model without a migration for every idea. |
| 📡 **Event backbone** | A first-class domain event bus (publish/subscribe, sagas, projections) so modules stay decoupled and workflows are legible. |
| 🧾 **Audit** | Every change — who, what, when, in which tenant — recorded by default. |
| 🖥️ **Admin surface** | An internal console generated from your models, not a second app to maintain. |
| 🤖 **Agent conventions** | An `AGENTS.md`, an opencode/Claude/Codex agent pack, and strict patterns so an AI agent can add a domain feature **safely** — and a human can read what it did. |

You write the **20% that is your business**. Loam is the 80% that every business
app shares.

---

## Agent-native by design

Loam treats "an AI agent will extend this" as a first-class constraint:

- **One obvious way** to add an entity, a permission, an event, a screen — so an
  agent's output is predictable and reviewable.
- **A shipped agent pack** (specs → implementation, guardrails, MCP schema access)
  so agents see the live model, routes, and policies.
- **Boundaries agents can't accidentally cross** — tenancy and permissions are
  structural, not conventions an agent might forget.

The result: a codebase where "add a `Subscription` entity with an admin screen,
tenant-scoped, audited, emitting `subscription.created`" is a *small, safe* task —
for an agent or a human.

## Better together: Loam × [DevOrch](https://github.com/yourusername/devorch)

Two halves of one idea:

- **Loam** — the substrate you *build on*. Conventions that make a Rails business
  app coherent and agent-legible.
- **DevOrch** — the orchestrator you *build with*. Drives AI agents through
  implement → test → review → PR across your repos.

Point DevOrch at a Loam project and the loop closes: an agent extends a codebase
*designed* for agents to extend, inside a workflow *designed* to run them. The
soil and the gardener.

---

## Status

**Working prototype.** This repo holds the vision and design **and a running
first cut** of the core loop:

- `lib/` — the `loam` gem: `Loam::TenantRecord` (structural tenant isolation
  that raises `Loam::MissingTenantError` on any query without tenant context),
  `Loam::Policy` (roles + field-level `writable:` rules), `Loam::Auditable`
  (audit-by-default), `Loam::Events` (a `domain.thing.happened` event bus),
  `Loam::CustomFields` (migration-free fields via a runtime
  `Loam::FieldDefinition`, stored in a `custom_fields` json column and
  managed from an admin screen — no code deploy needed), `Loam::Lifecycle`
  (`Loam.on_tenant_created` hooks that seed a new tenant, replayable over
  existing tenants with `bin/rails loam:sync`), and the two
  generators that are the whole interface: `loam:install` and `loam:entity`.
- `demo/` — an equipment-rental demo app built with those generators, including
  the generated guardrail tests (tenant isolation, no-context-raises, a lint
  that fails on any non-scoped model or any `.unscoped` in `app/`).

Prototype deviation from [docs/architecture.md](docs/architecture.md), on
purpose: the pillars are minimal in-gem implementations rather than wrappers
around `acts_as_tenant`/`pundit`/`paper_trail`/Rails Event Store — smallest
possible surface to prove the conventions and the agent flow. Swapping proven
gems back in behind the same conventions is the roadmap, not a reversal.
The custom-fields storage type is the portable Rails `json` column (not
Postgres `jsonb`/GIN) since the demo runs on SQLite.

Try it:

```bash
cd demo && bundle install && bin/rails db:migrate db:seed
bin/rails test            # guardrail + entity tests
bin/rails server          # → http://localhost:3000/admin
```

- [Concept & positioning](docs/concept.md)
- [Architecture](docs/architecture.md)
- [Manifesto](docs/manifesto.md)

---

## Name

**Loam** — the dark, fertile soil prized for growing things. Not a market
(*mercato*); the *ground beneath* one. You don't admire loam — you plant in it and
something grows. That's the promise: rich ground, ready, so what you grow is the
thing that matters.

*MIT licensed (planned) — open-core, like the foundations it stands on.*
