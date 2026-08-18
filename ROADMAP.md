# Loam — Roadmap

The merge of two plans: the 90-day product & business plan
([LOAM_PLAN.md](LOAM_PLAN.md), the source of truth for scope and KPIs) and the
execution backlog in the [Loam GitHub project](https://github.com/orgs/DeliveristsIO/projects/7)
(L-numbered tasks). Statuses below reflect the repository as of 2026-08-18.

## Where we are

**Days 1–14 (Loam Core)** — the foundation from LOAM_PLAN.md, mapped to reality:

| Plan capability | Status | Where |
|---|---|---|
| Multi-tenancy (Organization → `Loam::Tenant`) | ✅ done | `Loam::TenantRecord`, structural isolation, raises without context |
| Membership + roles | ✅ done | `Loam::Membership` (role per tenant) |
| Permissions + policies | ✅ done | `Loam::Policy`, field-level `writable:` rules |
| Audit log | ✅ done | `Loam::Auditable`, on by default |
| Events | ✅ done | `Loam::Events` (`domain.thing.happened`) |
| Custom fields | ✅ done | `Loam::CustomFields` + `Loam::FieldDefinition`, migration-free |
| Tenant lifecycle | ✅ done | `Loam.on_tenant_created` + `bin/rails loam:sync` (L-701) |
| Generators as the interface | ✅ done | `loam:install`, `loam:entity` (plan calls it `loam:resource` — same thing) |
| Demo app, README, tests, CI | ✅ done | `demo/`, generator harness (`rake test`), `.github/workflows/ci.yml` (L-101..L-104) |
| Workflow (states, transitions, approvals) | ✅ done | `Loam::Workflow` DSL, role-gated transitions, transition events (L-801) |
| Notifications | ✅ done | `Loam::Notification` + `Loam::Notifications.notify/notify_role`, admin screen (L-802) |
| API + webhooks | ✅ done | `Loam::ApiToken` bearer auth, generated JSON controllers, signed webhooks (L-803, L-804) |
| Authentication | ✅ done | password login, membership-limited tenant picker, admin API tokens (L-805) |
| Comments + attachments | ✅ done | `Loam::Commentable`/`Loam::Attachable`, shared admin comments controller (L-806) |
| Search + UI primitives (filters, pagination) | ✅ done | `Loam::Searchable`, global admin search, index filter + pagination (L-807) |

Naming decision (2026-08-18): the isolation axis stays **`Loam::Tenant`** — the
precise technical term. A business-facing `Organization` layer can sit on top
later (the Frappe/Mercato pattern) without renaming the core.

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
