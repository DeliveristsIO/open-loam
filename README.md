# OpenLoam 🌱

**In short:** OpenLoam is a Rails starter kit for business apps — multi-tenancy,
permissions, audit trails, workflows, and an event bus already built in, so you
skip months of plumbing and start on real features. It's also AI-native:
convention-driven code that AI coding agents (Claude Code, Codex, etc.) can
safely extend, with human-approval gates before any agent write takes effect.

**The fertile Rails foundation where AI agents grow business software.**

📖 **Documentation: [deliveristsio.github.io/open-loam/](https://deliveristsio.github.io/open-loam/)**

---

## Why OpenLoam exists

Every serious back-office app — CRM, ERP, ops console, internal tool — re-derives
the same ~80%: who's the tenant, who's allowed, what changed and when, how do
modules talk, where's the admin. Teams burn months on this before shipping a
single thing a customer cares about.

And now a second shift: **AI coding agents** (Claude Code, Codex, opencode) can
write real features — *if* the codebase is legible to them. Sprawling, snowflake
architectures confuse agents as much as they confuse new hires. Convention is
what makes a codebase safe for an agent to extend.

OpenLoam fuses the two: **a pre-built business foundation that is deliberately
agent-legible.** Rails already leans convention-over-configuration — arguably the
most agent-friendly framework there is. OpenLoam extends that philosophy from "how to
structure a controller" up to "how a multi-tenant, permissioned, audited business
domain is built" — and ships the agent conventions to match.

## Where OpenLoam sits

The pieces exist in Rails, but scattered — foundation shape in Bullet Train and
the commerce products, an event backbone in Rails Event Store, custom-entity
modeling only inside commerce. No Rails project unifies them into a single,
agent-legible business foundation. The closest structural analogs live in other
stacks: Frappe/ERPNext in Python, and
**[Open Mercato](https://github.com/open-mercato/open-mercato)** in TypeScript —
whose module system and convention-first, agent-legible approach directly
inspired OpenLoam. OpenLoam brings that idea to Rails, the substrate it always suited.

---

## What's already decided

Each pillar ships as a convention with sane defaults, overridable when you truly
need to — never a blank page.

| Pillar | What you get, out of the box |
|--------|------------------------------|
| 🏢 **Multi-tenancy** | Tenant isolation baked into every query, background job, and event. New models are tenant-scoped by default; a missing tenant context raises, never silently widens a query. |
| 🔐 **Permissions & auth** | Password login, roles, policies, and field-level write access — declared, not hand-rolled per controller. Tenant selection limited to a user's memberships. Plus **feature-string permissions** (`OpenLoam::Permissions`): grant a role wildcard capability strings (`equipment.*`) and check `OpenLoam.can?("equipment.edit")` / `require_permission!` — deny-by-default, a finer layer under the coarse role. |
| 🌾 **Custom fields** | Define fields at runtime (a `custom_fields` JSON column + a `OpenLoam::FieldDefinition` row), so agents and admins extend a model without a migration for every idea. Filtering and sorting on a custom field is **index-backed** at scale via a typed read-model projection (`OpenLoam::CustomFieldIndex`), not a per-row JSON scan — with **coverage accounting** (is the index complete or drifting?), a read-time gap that **falls back to the authoritative source for correctness** and **self-heals** in the background (deduped), and an honest "results may be incomplete" signal while it does. A field can declare `readable_roles`: filtering or sorting on a field a role **may not read** is refused, so a filter can't become an **inference oracle** on a restricted value. |
| 🔀 **Workflow** | Declared states, transitions, and role-gated approvals on any entity; each transition emits an event and is audited. |
| 📡 **Event backbone** | A first-class domain event bus (`domain.thing.happened`, publish/subscribe) so modules stay decoupled and workflows are legible. Two subscriber tiers with a **formal contract**: *ephemeral* (`OpenLoam::Events.subscribe`, in-process, synchronous, best-effort) for cheap fan-out, and *durable* (`OpenLoam::DurableEvents.register`) which **persists each delivery as a row** in the event's tenant and hands it to a background job — **at-least-once with retry + backoff**, a **dead-letter** view with manual requeue, and a periodic **sweep** that redelivers a lost job (row state, not the queue, is the source of truth). A handler is resolved from a boot-time registry, never constantized from the stored row. |
| 🔔 **Notifications** | Tenant-scoped in-app notifications, created from events, surfaced in the admin. |
| 🔌 **API & webhooks** | Token-authenticated JSON API per entity (policy-aware) and per-tenant signed **outbound** webhooks on domain events. **Inbound** webhooks too: a public `/webhooks/:token` receiver that HMAC-verifies each call over the raw body, resists replays (a `(source, delivery-id)` idempotency ledger), answers every auth failure with a uniform `401`, and publishes the verified event onto the bus so durable subscribers react. |
| 🧾 **Audit** | Every change — who, what, when, in which tenant — recorded by default. |
| ↩️ **Undo / history** | The audit trail is an **undo stack**: each record's History screen reverts a change with one click, and the undo is itself recorded — so undoing an `undo` is redo. Walks back one step at a time (never clobbers a newer edit); **encrypted fields and workflow state are never reverted** here (state changes undo via the reverse transition). |
| 🗑️ **Soft-delete** | Deleting a record hides it instead of erasing it — excluded from every query by default, still tenant-scoped in the recycle bin, restorable, and recorded in the audit trail. |
| ⚙️ **Settings** | A key-value settings store with a global default and a per-tenant override — typed values, resolved override → global → default, cached per request, and never leaking between tenants. |
| 🚩 **Feature flags** | Runtime on/off capabilities per tenant for rollout or kill-switch — a global default plus per-tenant override, a `OpenLoam::Features.on?` guard, and an admin screen. Gates a **capability**, not a person — distinct from roles and policies. |
| 🔒 **Encryption at rest** | Mark a field `encrypts` and it is transparently AES-256-GCM encrypted with a **per-tenant** key (HKDF, KMS-pluggable) and decrypted on read — a DB dump leaks nothing and tenant A's key never opens tenant B's data. A keyed blind index keeps an encrypted email/phone findable by exact match; the audit trail records the change, never the value. |
| 🔑 **MFA & step-up auth** | TOTP second factor for admin login (RFC 6238, no dependency), with single-use recovery codes; the secret is encrypted per-user so it verifies in any tenant. `require_sudo!` re-challenges for sensitive actions within a short window — orthogonal to role. MFA can be required per role. Failed password / TOTP / sudo attempts are **rate-limited and locked out** (per-identifier, configurable), so an online brute-force of a 6-digit code is throttled — and a lockout is enumeration-safe (a locked known and unknown identifier respond identically). |
| 🚦 **AI approval gate** | An agent running under confirm-mode **stages** a write as a `PendingAction` with a before/after preview instead of committing it; a manager approves (a role-gated workflow transition) and only then does it execute — audited to the approver. The human-in-the-loop primitive for agent writes; encrypted fields never appear in the preview or audit. |
| 🤖 **MCP server** | An [MCP](https://modelcontextprotocol.io) server (`bin/rails open_loam:mcp:serve`, stdio) exposes OpenLoam to an AI agent: discover entities/schema/policy, **read** tenant-scoped records (only fields the role may see), and **propose** writes that are *staged for human approval* — never committed. Every gate is a OpenLoam gate reused (tenancy, read-ACL, the approval gate); the agent acts as its API token's user, no more. |
| 👓 **Saved views** | A user names a view of an entity's admin index — filters, sort, columns — and keeps it private, shares it to a role, or makes it the tenant default. Filters only ever touch whitelisted data columns; a stored view is optimistic-locked so shared edits don't clobber. |
| 🔏 **Concurrent-edit safety** | Optimistic locking (`lock_version`) turns a stale save into a clean "this changed since you opened it" conflict — with a diff and a retry, never a silent clobber — and an advisory `RecordLock` shows "Anna is editing this" with a manager take-over. The version check is the guarantee; the lock is the courtesy. |
| 📡 **Real-time updates** | A per-tenant Server-Sent-Events stream pushes selected events to the browser — the notification bell increments live, no polling. Opt-in per event pattern (default off, tenant- and audience-filtered), behind a broadcaster seam so Redis/SolidCable drops in for multi-process. |
| 🧩 **Response enrichers** | One module attaches a computed block onto another's entity at read time — no foreign-key coupling (billing annotates an Equipment without Equipment knowing billing exists). A batch path resolves N records in one query; a failing enricher is isolated, and each runs tenant-scoped. |
| ⚡ **Business rules** | A manager declares, per tenant, WHEN a condition holds THEN run actions — evaluated on domain events, no deploy. The condition is **data, never code**: a whitelisted `{field, op, value}` tree over real columns and custom fields (no `eval`, no `send`, tenant/encrypted columns refused), and the actions are a fixed safe vocabulary (notify, emit an event, set a whitelisted field, veto a transition). Rules fire tenant-scoped in priority order, each isolated, with an execution log that shows why it acted. |
| 🔎 **Pluggable search** | `searchable_by` and `Model.search(q)` stay put; the strategy behind them is a swappable **driver**. Ships two: a portable substring **LIKE** (default, zero-setup) and a **word-level token index** (order-independent, AND-semantics, still plain SQL — no external service), with the seam ready for Meilisearch/Elasticsearch. Swapping is a one-line initializer change, no call-site edits. Tenant-scoped, and an encrypted field's plaintext is never tokenized. |
| 🪪 **SSO (OIDC)** | Per-tenant single sign-on: each tenant connects its own identity provider. **Home-realm discovery** routes a user to their IdP by email domain; a verified identity is **just-in-time provisioned** (or linked to an existing account), with IdP group → role mapping. The client secret is encrypted at rest (per-tenant key). An unverified email is refused — no silent account takeover. OIDC ships end-to-end; SAML and SCIM are documented seams behind a protocol interface. |
| 📚 **Dictionaries** | Per-tenant managed lookup lists — named sets of entries (value/label/color/icon/position/default) an admin curates without a deploy. Usable as a **custom-field type**: a `dictionary` field renders a select of the list's active entries and stores the chosen value, showing its label on read. Tenant-scoped and cached per request. |
| ⏳ **Task progress** | A long-running job (import, reindex, report) reports percent / counts / ETA to the admin, pushed **live over SSE** — no polling. `OpenLoam::Progress.start`/`advance`/`complete!`; the browser bar moves as the job runs. The broadcast is throttled to once per whole percent, the job supports a cooperative cancel, and a stalled job (dead heartbeat) is flagged. Tenant-scoped; the frame carries only id/percent/status. |
| 🕰️ **Scheduler** | Per-tenant recurring jobs — cron (`0 7 * * *`) or interval — that enqueue an ActiveJob on schedule. A runner (`open_loam:scheduler:tick`, wired to system cron) claims due jobs **atomically** (Postgres `SKIP LOCKED`; SQLite a transactional claim), so multiple workers **never double-fire** one. `job_class` is whitelisted to a real ActiveJob (no arbitrary code). Tenant-scope jobs run per tenant; system-scope once. A stdlib cron-next calculator (no gem), timezone-aware. |
| 📥 **Bulk import / export** | CSV **export** of any entity's current filtered view — policy- and encryption-aware (an encrypted field is redacted, never a plaintext dump). CSV **import** with a column-mapping engine: dedupe by a key (update-or-create), per-row validation with a skipped-row error log and a **downloadable error file**, a **dry-run** that commits nothing, and live progress (backgrounded, reported via the task bar). The mapping only targets policy-permitted fields — no crafted column reaches `tenant_id` or a field a role can't write. Plus **datatable bulk actions** (select rows → soft-delete / set-field / export), policy-checked per record and tenant-scoped. |
| 📊 **Configurable dashboard** | The admin home is a grid of module-provided **widgets** on a registry — a metric or short list each. A manager picks which widgets appear and in what order, per tenant; a widget's `roles:` filter is enforced server-side (a hidden widget's data is never even computed). Widgets query tenant-scoped models (no cross-tenant leak), and a raising widget is isolated into an error tile — the dashboard never breaks. Ships built-ins (recent activity, unread notifications, pending approvals, running tasks). |
| 📜 **Auto OpenAPI** | The JSON API documents itself. `OpenLoam::OpenApi` introspects the generated per-entity API controllers — columns/types, exposed fields, custom fields, the bearer-token security scheme, and the tenancy guarantee — into an **OpenAPI 3.1** document, with **no hand-written annotations and no external gem**. A server-rendered explorer at `/admin/api_docs` (no Swagger-UI/external JS), a `.json` endpoint for tooling, and `open_loam:openapi:export` for CI. Request schemas expose only writable fields (never `tenant_id`); encrypted fields are typed as plain strings — the doc describes shape, never data. |
| 🌐 **Content translations** | Translate the DATA in a record's fields per locale — a product name, a category label — distinct from Rails i18n (developer UI strings, still Rails-native). `translates :name` adds a read-time **overlay**: `record.name` returns the current locale's translation when one exists, else the record's own column (the base value, never lost). Locale is request state (a `/admin` switcher); translations are tenant-scoped, audited, additive rows. An **encrypted field can't be translated** — that would store plaintext, so it's refused at load. |
| 🧬 **Override registry** | Disable or replace an entry in one of OpenLoam's keyed registries — a built-in dashboard widget, a default broadcast pattern — from an initializer, **without forking or monkeypatching**: `OpenLoam::Overrides.disable(:widgets, "open_progress")` / `.replace(:widgets, "audit_recent") { … }`. The value over a raw monkeypatch: a **stale override** (a key that no longer exists) is warned about at boot, so a typo isn't a silent no-op. Deliberately small — structural pieces (views, controllers, routes) still use standard Rails path-shadowing; this fills the gap for the in-gem registries. |
| 🖥️ **Admin surface** | An internal console generated from your models — comments, attachments, global search, filtering, pagination — not a second app to maintain. |
| 🤖 **Agent conventions** | An `AGENTS.md` (byte-budgeted), generators as the one interface, and structural guardrails so an AI agent can add a domain feature **safely** — and a human can read what it did. |

You write the **20% that is your business**. OpenLoam is the 80% that every business
app shares.

---

## Agent-native by design

OpenLoam treats "an AI agent will extend this" as a first-class constraint:

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

**Working prototype — every pillar in the table above is built, tested, and
exercised end to end** by a demo app, a generator harness, and an agent
benchmark. Some two dozen `OpenLoam::` modules, from tenancy through SSO, each
added the same way: a small in-gem implementation behind a convention, wired to
agree with the rest.

**What's in the repo**

| Path | What it is |
|------|-----------|
| `lib/` | The `open_loam` gem — every pillar as a small `OpenLoam::` module, plus the `open_loam:install` and `open_loam:entity` generators that are the whole interface. |
| `demo/` | An equipment-rental app built with those generators (454 tests / 1,534 assertions as of 2026-08-22), carrying the generated guardrail tests: tenant isolation, no-context-raises, a lint against `.unscoped` in `app/`, and a 32 KB `AGENTS.md` budget. |
| `ai/` | The agent benchmark — `golden_tasks.md` and recorded runs. First run: **10/10 tasks, zero isolation or authorization violations**; a vanilla-Rails control under the same prompts enforced isolation in **1/10**. |
| `docs/_agents/` | Deep-dive conventions (encryption, SSO, scheduler, …) linked from `AGENTS.md`, so the agent contract stays inside its byte budget. |
| `.github/` | CI runs the generator harness and the demo suite on every push. |

**Security-hardened by adversarial review.** Each batch of features went through
an independent adversarial security review; the reviews found and closed real
cross-tenant account-takeover chains, privilege escalations, and PII-leak
vectors — every fix landing with a regression test that reproduces the exploit.
That the *power* features (a business-rules engine, bulk import, SSO) are where
the holes appeared, and that the guardrails and reviews caught them, is the
whole thesis in miniature.

**How honest the "prototype" label is** — deliberately, each pillar is a
*minimal in-gem implementation* rather than a wrapper around
`acts_as_tenant`/`pundit`/`paper_trail`/Rails Event Store: the smallest surface
that proves the conventions and the agent flow. Those swaps have since been
evaluated one at a time and settled — the in-gem versions stay, and the one real
gap they exposed (event capture) was closed in-gem too, in
[ADR 0007](docs/_adr/0007-proven-gem-swaps-resolved.md). Custom
fields use the portable Rails `json` column (not Postgres `jsonb`/GIN) because
the demo runs on SQLite. See [How OpenLoam works](docs/_foundation/overview.md) for
the pillar-by-pillar breakdown and the decisions behind them.

**Try it**

```bash
cd demo && bundle install && bin/rails db:migrate db:seed
bin/rails test            # guardrail + entity tests
bin/rails server          # → http://localhost:3000/admin
```

Sign in as `anna@example.com` (manager in both branches, so she gets the tenant
picker) or `tomek@example.com` (Warsaw only) — password `password123` for both.

**New here? Start with the [Getting Started walkthrough](https://deliveristsio.github.io/open-loam/getting-started/)** —
it builds a multi-tenant feature from `rails new` to a working approval flow,
showing the real commands and exactly what you *didn't* have to write.

- [**Architecture map**](https://claude.ai/code/artifact/949311d3-5e14-4f07-a8ad-7b1bb5bd87ad) — a visual tour: the module graph, a request lifecycle, the event flow
- [Getting started](https://deliveristsio.github.io/open-loam/getting-started/) — hands-on, install to first feature
- [Overview](OVERVIEW.md) — plain-language product, use cases, evidence, and risks
- [Concept & positioning](https://deliveristsio.github.io/open-loam/concept/)
- [How OpenLoam works](https://deliveristsio.github.io/open-loam/foundation/overview/) — the diagrams above + how every pillar is built
- [Tenant isolation](https://deliveristsio.github.io/open-loam/foundation/tenant-isolation/) & [Authorization](https://deliveristsio.github.io/open-loam/foundation/authorization/) — the two flagship guarantees, in depth
- [Agents](https://deliveristsio.github.io/open-loam/agents/) — the agent contract, guardrails, the golden-tasks benchmark, and subsystem deep-dives (encryption, SSO, scheduler, events, inbound webhooks, bulk, confirm-mode)
- Reference — [configuration](https://deliveristsio.github.io/open-loam/reference/configuration/), [generators](https://deliveristsio.github.io/open-loam/reference/generators/), [backward compatibility](https://deliveristsio.github.io/open-loam/reference/compatibility/)
- [Roadmap](ROADMAP.md) — ordered backlog, Mercato-informed
- [Backward-compatibility contract](BACKWARD_COMPATIBILITY.md) — the frozen public surfaces
- [Architecture decisions](https://deliveristsio.github.io/open-loam/adr/) & [lessons](ai/lessons.md) — why things are the way they are, and the gotchas
- [Agent pack](.open_loam/agents/) — everything an AI agent should load to extend a OpenLoam app correctly
- [Manifesto](https://deliveristsio.github.io/open-loam/manifesto/)
- [Contributing](CONTRIBUTING.md)

---

*MIT licensed — open-core, like the foundations it stands on.*
