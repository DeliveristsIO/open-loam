# Loam — Roadmap

The merge of two plans: the 90-day product & business plan
([LOAM_PLAN.md](LOAM_PLAN.md), the source of truth for scope and KPIs) and the
execution backlog in the [Loam GitHub project](https://github.com/orgs/DeliveristsIO/projects/7)
(L-numbered tasks). Statuses below reflect the repository as of 2026-08-21.

## Where we are

**The technical foundation is far ahead of the plan.** LOAM_PLAN.md's Days 1–14
core is long done; on top of it, four batches of features shipped — some two
dozen `Loam::` modules in all — each added behind a convention, tested, and
run through an independent adversarial security review.

| Batch | Modules | Status |
|---|---|---|
| **Days 1–14 core** | tenancy, membership/roles, policies, audit, events, custom fields, lifecycle, workflow, notifications, API + webhooks, auth, comments/attachments, search, generators, demo, CI | ✅ done (L-101…L-807, L-701/702) |
| **NOW** (regulated + agent-native) | soft-delete, per-tenant configs, feature flags, **per-tenant field encryption (AES-256-GCM + AAD)**, MFA + step-up, AI mutation approval gate | ✅ done (L-901–906) |
| **NEXT** (platform) | saved views, record locks, real-time SSE, response enrichers, business-rules engine, pluggable search, **SSO (OIDC + JIT)** | ✅ done (L-907–913) |
| **LATER** | dictionaries, task progress, scheduler, bulk import/export, dashboards + widgets, auto-OpenAPI, content translations, override registry | ✅ done (L-914–922) |
| **Deferred security** | auth rate-limiting/lockout, ciphertext AAD binding | ✅ done (L-923–924) |

Three adversarial security reviews (one per batch) plus two deferred-item passes
found and closed **4 CRITICAL + 3 HIGH** cross-tenant account-takeover chains,
privilege escalations, and PII-leak vectors — each fix shipped with a regression
test that reproduces the exploit. The demo suite carries ~1,300 assertions; CI
is green.

Naming decision: the isolation axis stays **`Loam::Tenant`** — the precise
technical term. A business-facing `Organization` layer can sit on top later
(the Frappe/Mercato pattern) without renaming the core.

**The honest gap is not features — it's validation.** None of this has been used
on a real project yet. The single highest-value next step is one measured
dogfood build (LOAM_PLAN.md Days 61–75), not another module.

## Next phases (from LOAM_PLAN.md, unchanged)

- **Days 15–30 — Developer Experience**: richer generator output (filtering,
  API, UI in one command), reusable primitives. Backlog: L-401 (pagination/
  search in admin), L-402 (shared styles).
- **Days 31–45 — AI Layer**: `.loam/ai/` with golden tasks (list already in
  the repo — see `ai/golden_tasks.md`), benchmark runs with metrics
  (completion, test pass rate, violations, interventions). Backlog: L-301
  (agent pack), L-303 (scripted eval), L-708 (specs-as-ADRs). MCP (L-302)
  after the first eval says whether it's needed.
- **Days 46–60 — Reference CRM module**: Company/Contact/Lead/Opportunity/
  Pipeline/Task/Activity, deliberately small, proves the primitives compose.
  Backlog: L-501 (second domain demo) folds into this.
- **Days 61–75 — Deliverists dogfooding**: ≥1 real project, measure vanilla
  Rails estimate vs Loam+AI actual. Target ≥25–30% time reduction — the kill
  criterion lives here.
- **Days 76–90 — Public launch**: docs site, landing, the two demos
  ("rails new → multi-tenant app in 10 minutes" and "agent implements
  purchase orders from a business requirement").

## Hardening backlog fed by the Open Mercato research (L-7xx)

- L-703 read-model index for custom fields (filter/sort at scale)
- L-704 command pattern with undo/redo on top of the audit trail
- L-705 feature-string permissions with wildcards
- L-706 formal ephemeral vs persistent event subscriber contract
- L-707 frozen contract inventory (BACKWARD_COMPATIBILITY.md)
- L-708 specs-as-ADRs + lessons.md convention

## Explicit non-goals for V1 (from LOAM_PLAN.md)

Billing, accounting, warehouse, ecommerce, marketplace, payroll, full ERP,
full CRM, low-code builder. Modules later; the core stays small.

## Guiding principle

> Does this make Loam better at building business software repeatedly and
> predictably? If no, it does not belong in the core.
