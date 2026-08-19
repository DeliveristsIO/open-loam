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
| 🏢 **Multi-tenancy** | Tenant isolation baked into every query, background job, and event. New models are tenant-scoped by default; a missing tenant context raises, never silently widens a query. |
| 🔐 **Permissions & auth** | Password login, roles, policies, and field-level write access — declared, not hand-rolled per controller. Tenant selection limited to a user's memberships. |
| 🌾 **Custom fields** | Define fields at runtime (a `custom_fields` JSON column + a `Loam::FieldDefinition` row), so agents and admins extend a model without a migration for every idea. |
| 🔀 **Workflow** | Declared states, transitions, and role-gated approvals on any entity; each transition emits an event and is audited. |
| 📡 **Event backbone** | A first-class domain event bus (`domain.thing.happened`, publish/subscribe) so modules stay decoupled and workflows are legible. |
| 🔔 **Notifications** | Tenant-scoped in-app notifications, created from events, surfaced in the admin. |
| 🔌 **API & webhooks** | Token-authenticated JSON API per entity (policy-aware) and per-tenant signed outbound webhooks on domain events. |
| 🧾 **Audit** | Every change — who, what, when, in which tenant — recorded by default. |
| 🖥️ **Admin surface** | An internal console generated from your models — comments, attachments, global search, filtering, pagination — not a second app to maintain. |
| 🤖 **Agent conventions** | An `AGENTS.md` (byte-budgeted), generators as the one interface, and structural guardrails so an AI agent can add a domain feature **safely** — and a human can read what it did. |

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

- `lib/` — the `loam` gem. Core: `Loam::TenantRecord` (structural tenant
  isolation that raises `Loam::MissingTenantError` on any query without tenant
  context), `Loam::Policy` (roles + field-level `writable:` rules),
  `Loam::Auditable` (audit-by-default), `Loam::Events` (a
  `domain.thing.happened` event bus), `Loam::CustomFields` (migration-free
  fields via a runtime `Loam::FieldDefinition` in a `custom_fields` json
  column, managed from an admin screen), and `Loam::Lifecycle`
  (`Loam.on_tenant_created` hooks, replayable with `bin/rails loam:sync`).
  Business layer: `Loam::Workflow` (states, transitions, role-gated
  approvals), `Loam::Notifications`, a token-authenticated REST API,
  `Loam::Webhooks` (per-tenant signed outbound delivery), `Loam::Commentable`,
  `Loam::Attachable` (ActiveStorage), `Loam::Searchable` (+ index filtering and
  pagination), and password authentication for the admin. The whole interface
  is two generators: `loam:install` and `loam:entity`.
- `demo/` — an equipment-rental demo app built with those generators, including
  the generated guardrail tests (tenant isolation, no-context-raises, a lint
  that fails on any non-scoped model or any `.unscoped` in `app/`, and a 32 KB
  budget on `AGENTS.md`).
- `ai/` — the agent benchmark: `golden_tasks.md` plus recorded runs under
  `benchmark_runs/`. The first run (10 golden tasks, one agent each on isolated
  apps) completed 10/10 with zero tenant-isolation or authorization violations;
  a vanilla-Rails control run under the same prompts enforced isolation in only
  1 of 10 apps. See `ai/benchmark_runs/`.
- CI (`.github/workflows/ci.yml`) runs the generator harness and the demo suite
  on every push.

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

Sign in as `anna@example.com` (manager in both branches, so she gets the tenant
picker) or `tomek@example.com` (Warsaw only) — password `password123` for both.

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
