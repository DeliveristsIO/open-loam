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

## Where Loam sits

The pieces exist in Rails, but scattered — foundation shape in Bullet Train and
the commerce products, an event backbone in Rails Event Store, custom-entity
modeling only inside commerce. No Rails project unifies them into a single,
agent-legible business foundation. The closest structural analogs live in other
stacks: Frappe/ERPNext in Python, and
**[Open Mercato](https://github.com/open-mercato/open-mercato)** in TypeScript —
whose module system and convention-first, agent-legible approach directly
inspired Loam. Loam brings that idea to Rails, the substrate it always suited.

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
| 🗑️ **Soft-delete** | Deleting a record hides it instead of erasing it — excluded from every query by default, still tenant-scoped in the recycle bin, restorable, and recorded in the audit trail. |
| ⚙️ **Settings** | A key-value settings store with a global default and a per-tenant override — typed values, resolved override → global → default, cached per request, and never leaking between tenants. |
| 🚩 **Feature flags** | Runtime on/off capabilities per tenant for rollout or kill-switch — a global default plus per-tenant override, a `Loam::Features.on?` guard, and an admin screen. Gates a **capability**, not a person — distinct from roles and policies. |
| 🔒 **Encryption at rest** | Mark a field `encrypts` and it is transparently AES-256-GCM encrypted with a **per-tenant** key (HKDF, KMS-pluggable) and decrypted on read — a DB dump leaks nothing and tenant A's key never opens tenant B's data. A keyed blind index keeps an encrypted email/phone findable by exact match; the audit trail records the change, never the value. |
| 🔑 **MFA & step-up auth** | TOTP second factor for admin login (RFC 6238, no dependency), with single-use recovery codes; the secret is encrypted per-user so it verifies in any tenant. `require_sudo!` re-challenges for sensitive actions within a short window — orthogonal to role. MFA can be required per role. |
| 🚦 **AI approval gate** | An agent running under confirm-mode **stages** a write as a `PendingAction` with a before/after preview instead of committing it; a manager approves (a role-gated workflow transition) and only then does it execute — audited to the approver. The human-in-the-loop primitive for agent writes; encrypted fields never appear in the preview or audit. |
| 🖥️ **Admin surface** | An internal console generated from your models — comments, attachments, global search, filtering, pagination — not a second app to maintain. |
| 🤖 **Agent conventions** | An `AGENTS.md` (byte-budgeted), generators as the one interface, and structural guardrails so an AI agent can add a domain feature **safely** — and a human can read what it did. |

You write the **20% that is your business**. Loam is the 80% that every business
app shares.

---

## Agent-native by design

Loam treats "an AI agent will extend this" as a first-class constraint:

- **One obvious way** to add an entity, a permission, an event, a screen — so an
  agent's output is predictable and reviewable.
- **A contract they read** — an `AGENTS.md` map plus generators as the only
  interface, so an agent extends the app the same way every time. (Live schema
  access over MCP is on the roadmap.)
- **Boundaries agents can't accidentally cross** — tenancy and permissions are
  structural, not conventions an agent might forget.

The result: a codebase where "add a `Subscription` entity with an admin screen,
tenant-scoped, audited, emitting `subscription.created`" is a *small, safe* task —
for an agent or a human.

---

## Status

**Working prototype — the full Days 1–14 core runs end to end.** The pillars
above aren't a plan; they're built, tested, and exercised by a demo app and an
agent benchmark.

**What's in the repo**

| Path | What it is |
|------|-----------|
| `lib/` | The `loam` gem — every pillar as a small `Loam::` module, plus the `loam:install` and `loam:entity` generators that are the whole interface. |
| `demo/` | An equipment-rental app built with those generators, carrying the generated guardrail tests (tenant isolation, no-context-raises, a lint against `.unscoped` in `app/`, a 32 KB `AGENTS.md` budget). |
| `ai/` | The agent benchmark — `golden_tasks.md` and recorded runs. First run: **10/10 tasks, zero isolation or authorization violations**; a vanilla-Rails control under the same prompts enforced isolation in **1/10**. |
| `.github/` | CI runs the generator harness and the demo suite on every push. |

**How honest the "prototype" label is** — deliberately, each pillar is a
*minimal in-gem implementation* rather than a wrapper around
`acts_as_tenant`/`pundit`/`paper_trail`/Rails Event Store: the smallest surface
that proves the conventions and the agent flow. Swapping the proven gems back in
*behind the same `Loam::` conventions* is the roadmap, not a reversal. Custom
fields use the portable Rails `json` column (not Postgres `jsonb`/GIN) because
the demo runs on SQLite. See [docs/architecture.md](docs/architecture.md) for
the pillar-by-pillar breakdown and the decisions behind them.

**Try it**

```bash
cd demo && bundle install && bin/rails db:migrate db:seed
bin/rails test            # guardrail + entity tests
bin/rails server          # → http://localhost:3000/admin
```

Sign in as `anna@example.com` (manager in both branches, so she gets the tenant
picker) or `tomek@example.com` (Warsaw only) — password `password123` for both.

**New here? Start with the [Getting Started walkthrough](docs/getting-started.md)** —
it builds a multi-tenant feature from `rails new` to a working approval flow,
showing the real commands and exactly what you *didn't* have to write.

- [Getting started](docs/getting-started.md) — hands-on, install to first feature
- [Concept & positioning](docs/concept.md)
- [Architecture](docs/architecture.md)
- [Manifesto](docs/manifesto.md)
- [Contributing](CONTRIBUTING.md)

---

*MIT licensed — open-core, like the foundations it stands on.*
