# Loam — Roadmap

The merge of two plans: the 90-day product & business plan
([LOAM_PLAN.md](LOAM_PLAN.md), the source of truth for scope and KPIs) and the
execution backlog in the [Loam GitHub project](https://github.com/orgs/DeliveristsIO/projects/7)
(L-numbered tasks). Statuses below reflect the repository as of 2026-08-22.

## Where we are

**The technical foundation is far ahead of the plan.** LOAM_PLAN.md's Days 1–14
core is long done; on top of it, six batches of features shipped — roughly thirty
`Loam::` modules in all — each added behind a convention, tested, and run
through an independent adversarial security review.

| Batch | Modules | Status |
|---|---|---|
| **Days 1–14 core** | tenancy, membership/roles, policies, audit, events, custom fields, lifecycle, workflow, notifications, API + webhooks, auth, comments/attachments, search, generators, demo, CI | ✅ done (L-101…L-807, L-701/702) |
| **NOW** (regulated + agent-native) | soft-delete, per-tenant configs, feature flags, **per-tenant field encryption (AES-256-GCM + AAD)**, MFA + step-up, AI mutation approval gate | ✅ done (L-901–906) |
| **NEXT** (platform) | saved views, record locks, real-time SSE, response enrichers, business-rules engine, pluggable search, **SSO (OIDC + JIT)** | ✅ done (L-907–913) |
| **LATER** | dictionaries, task progress, scheduler, bulk import/export, dashboards + widgets, auto-OpenAPI, content translations, override registry | ✅ done (L-914–922) |
| **Hardening** | auth rate-limiting/lockout, ciphertext AAD binding, read-model custom-field index (coverage + self-heal), **durable event subscribers (retry + dead-letter)**, **custom-field read ACL (index oracle guard)** | ✅ done (L-923–924, L-703, L-919, **L-706**, **L-711**) |

Three adversarial security reviews (one per feature batch) plus deferred-item
passes found and closed **4 CRITICAL + 3 HIGH** cross-tenant account-takeover
chains, privilege escalations, and PII-leak vectors — each fix shipped with a
regression test that reproduces the exploit. The demo suite carries ~1,400
assertions; CI is green.

Naming decision: the isolation axis stays **`Loam::Tenant`** — the precise
technical term. A business-facing `Organization` layer can sit on top later
(the Frappe/Mercato pattern) without renaming the core.

A later **polish & agent-legibility** batch also shipped: inbound webhooks,
custom-field read ACL, sortable/filter-stable admin index, full i18n of the
generated UI, undo/redo on the audit trail, wildcard feature-permissions, an
observability seam, a shared admin stylesheet, the frozen-contract inventory,
the ADR + lessons conventions, the agent pack, and the eval scorer
(L-301, L-303, L-401, L-402, L-403, L-704, L-705, L-706, L-707, L-708, L-710,
L-711, L-712, L-713). The demo suite carries ~1,530 assertions; CI is green.

**The honest gap is not features — it's validation.** None of this has been used
on a real project yet. The single highest-value next step is one measured
dogfood build (LOAM_PLAN.md Days 61–75, ticketed as **L-709**), not another
module. **The remaining open tickets are deferred by design, not overlooked:**
the gem-wrapping refactors (L-201…L-204) would replace the working, tested
tenancy/policy/audit/event *spine* with third-party dependencies for no
user-facing gain (ADR [0002](docs/adr/0002-in-gem-implementations.md) — do them
only when a proven gem adds something the in-gem version lacks); the MCP server
(L-302) is gated on the dogfood signal (which tools an agent actually reaches
for); the reference-CRM second domain (L-501) is a deliberate build that folds
into the dogfood; and monetization (L-601…L-603) awaits a business decision.
Everything below is ordered with that in mind.

## What the Open Mercato 0.7 research changed

Comparing Loam against Open Mercato's August 2026 (0.7.0) release: Loam already
matches its foundation — multi-tenancy, RBAC, custom-fields with a hybrid index
(`Loam::CustomFieldIndex`, coverage + self-heal), event backbone, encryption in
the ORM lifecycle, overlay overrides, the AI mutation-approval gate. Mercato 0.7
surfaced three things worth having that Loam did **not** — now ticketed:

- **Durable/async event subscribers** — Mercato runs persistent subscribers
  (local or Redis). Loam's were in-process only. **Shipped as L-706.**
- **Inbound webhook receiver** — Loam signs *outbound* webhooks but had no
  bounded, replay-resistant path to *receive* them. **L-710.**
- **Query-index ACL** — Mercato's "ACL-enforced results" prevents a filter from
  leaking values a role can't read. Loam's index never exposes encrypted data,
  but filtering on an unreadable field was an inference oracle. **Shipped as L-711.**

Explicitly **not** adopted (Mercato features that are product/vertical, not
foundation): pgvector/semantic search, mobile push + device registry, the
EUDR/WMS/RMA domain packs, the Figma component gallery. Observability (OTLP) is
worth a small seam — **L-712** — but low priority.

## The ordered backlog

Ordered by value. GitHub issues are created in this order, so a lower issue
number = higher priority.

### P0 — Validation (do this before any new module)
- **L-709 — Dogfood: one measured real build.** Build one real Deliverists
  process on Loam+AI; measure the vanilla-Rails estimate vs the Loam actual.
  Target ≥25–30% time reduction — the **kill criterion** for the whole thesis
  (LOAM_PLAN.md Days 61–75). It also *tells us* which gap below to build next
  instead of guessing.

### P1 — Foundational + user-facing gaps
- ~~L-713 — i18n-friendly generated UI~~ (user-flagged priority) — ✅ shipped:
  a `loam.*` base locale ships in the gem, the switcher drives `I18n.locale`
  (chrome + content), and the whole generated surface — admin layout + every
  `loam:entity` view and its flashes — is `t()`-wrapped (model/field names via
  Rails `activerecord.*`). Demo proves a Polish round-trip. *Remaining (minor):*
  the gem's own built-in admin screens (scheduler, webhooks, …) stay English.
- ~~L-710 — Inbound webhook receiver~~ — ✅ shipped: public `/webhooks/:token`,
  HMAC over the raw body, `(source, delivery-id)` replay ledger, uniform 401,
  published onto the event bus. See `docs/agents/inbound-webhooks.md`.
- ~~L-711 — Custom-field index ACL~~ — ✅ shipped (see Hardening above).

### P2 — AI layer (the on-brand differentiator; gate depth on L-709's signal)
- **L-302 — MCP server** for live schema/entity/policy introspection. Mercato
  shipped an AI harness + MCP; this is our most on-brand move. Build it after the
  dogfood run shows which tools an agent actually reaches for.
- ~~L-301 — `.loam/agents/` pack~~ — ✅ shipped: `.loam/agents/README.md` is the
  pack index/manifest tying together AGENTS.md, lessons, ADRs, deep-dives, the
  contract inventory, and the golden-task benchmark, with a load order.
- ~~L-303 — scripted "agent adds a feature" eval~~ — ✅ shipped: `Loam::Eval`
  + `bin/rails loam:eval[task]` score a run (green suite AND no invariant
  violated) into a machine-readable scorecard under `ai/benchmark_runs/`.

### P3 — Hardening backlog (fed by the Open Mercato research)
- ~~L-704 — undo/redo on the audit trail~~ — ✅ shipped: `Loam::Undo` + a
  per-record History screen; undo records itself (redo = undo the undo), with
  stack-order / encrypted / workflow-column guardrails.
- ~~L-705 — feature-string permissions with wildcards~~ — ✅ shipped:
  `Loam::Permissions` (role → wildcard capability strings), `Loam.can?` /
  `require_permission!` / `can?` helper, deny-by-default.
- ~~L-707 — frozen contract inventory~~ — ✅ shipped: `BACKWARD_COMPATIBILITY.md`
  catalogues every frozen public surface (tenancy, events, generators, policy,
  encryption format, webhook signature, API, custom fields, audit/undo, …).
- ~~L-708 — specs-as-ADRs + `lessons.md`~~ — ✅ shipped: `docs/adr/` (convention +
  template + 5 seed ADRs) and `ai/lessons.md` (the framework's real gotchas),
  referenced from `AGENTS.md`.
- ~~L-712 — observability seam~~ — ✅ shipped: `Loam::Telemetry.span` wraps the
  scheduler tick, durable delivery, and inbound ingest; default emits
  `loam.span.*` notifications, pluggable to OTLP via `Telemetry.backend`.

### P4 — Admin & UX polish
- ~~L-401 — pagination + search on generated admin index views~~ — ✅ shipped:
  sortable columns (whitelisted, SQLi-safe) + full filter state carried through
  paging/export.
- ~~L-402 — extract inline admin CSS to a shared stylesheet~~ — ✅ shipped:
  `admin.css` + flash rendering in the layout.
- ~~L-403 — spike: evaluate Avo as an alternate admin backend~~ — ✅ done:
  [ADR 0006](docs/adr/0006-avo-admin-evaluation.md) — keep the generated admin
  (tenancy + field-policy stay structural); Avo stays an app-level option.

### P5 — Prove domain-agnosticism
- **L-501** a second demo app in a different domain (folds into the LOAM_PLAN
  reference CRM module).

### P6 — Swap in proven gems (a refactor, not a feature — do last)
- **L-201** evaluate & wrap `acts_as_tenant` behind `Loam::TenantRecord`.
- **L-202** wrap Pundit behind `Loam::Policy`'s field DSL.
- **L-203** wrap `paper_trail` behind `Loam::Auditable`.
- **L-204** wrap Rails Event Store behind `Loam::Events`.

### P7 — Monetization infrastructure
- **L-601** `loam-enterprise` extension-point skeleton.
- **L-602** one-click Managed hosting deploy.
- **L-603** first Marketplace domain pack.

## Non-goals for V1 (from LOAM_PLAN.md)

Billing, accounting, warehouse, ecommerce, marketplace, payroll, full ERP,
full CRM, low-code builder, semantic/vector search, mobile push. Modules later;
the core stays small.

## Guiding principle

> Does this make Loam better at building business software repeatedly and
> predictably? If no, it does not belong in the core.
