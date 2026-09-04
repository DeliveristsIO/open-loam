# Golden tasks run — 2026-08-19 — Claude (Fable 5 subagents)

First full run of the [golden tasks benchmark](../golden_tasks.md).

## Setup

- Baseline: fresh Rails 8.1.3 app + `open_loam:install` + `open_loam:entity Company`
  + `open_loam:entity PurchaseOrder` with a `OpenLoam::Workflow`
  (draft → submitted → approved, approve gated to `:manager`). Baseline suite:
  17 runs / 40 assertions, green.
- 10 isolated copies of the baseline, one agent per copy. Each agent received
  ONLY the app path and the business requirement; AGENTS.md was its sole
  contract. No implementation hints, no human intervention at any point.
- Every result verified independently by the orchestrator: full suite re-run
  from a clean shell + `.unscoped` grep over `app/` and the initializer.
- Task texts were adapted to the baseline domain where the canonical list
  references entities that don't exist in a fresh app (contacts → companies,
  rentals/damage reports → purchase orders). Semantics preserved.

## Results

| # | Task | Result | Suite (runs/assertions) | Wall time | Violations |
|---|------|--------|------------------------|-----------|------------|
| 1 | Approval above €10,000 | ✅ | 24/63 | ~6 min | 0 |
| 2 | Custom field on Company | ✅ | 26/64 | ~5 min | 0 |
| 3 | Manager-only CSV export | ✅ | 21/68 | ~4 min | 0 |
| 4 | Dashboard metric | ✅ | 21/57 | ~4 min | 0 |
| 5 | Webhook on status change | ✅ | 28/119 | ~6 min | 0 |
| 6 | REST endpoint (approved orders) | ✅ | 20/48 | ~5 min | 0 |
| 7 | Daily overdue-approval digest job | ✅ | 24/68 | ~4 min | 0 |
| 8 | Notify managers on submit | ✅ | 19/45 | ~4 min | 0 |
| 9 | New workflow state (suspended) | ✅ | 22/55 | ~2.5 min | 0 |
| 10 | Modify workflow (reason ≥ €5,000) | ✅ | 24/56 | ~5 min | 0 |

## Metrics vs targets

| Metric | Target | This run |
|---|---:|---:|
| Task completed | > 90% | **100% (10/10)** |
| Tests passing | > 95% | **100%** (every suite fully green, verified independently) |
| Architecture violations | < 5% | **0** (no `.unscoped`, no hand-created entity files, no direct workflow-column writes, guardrail tests green in all 10 apps) |
| Human interventions | decreasing | **0** |
| Wall time per task | — | 2.5–6 min |

## Qualitative observations

- **Agents composed primitives instead of reinventing.** Task 5 wrote no HTTP
  code — it recognized the existing webhook registry + workflow events and
  closed only the real gaps. Task 6 explicitly declined to add a tenant
  predicate ("that would have been the bug"): structural tenancy was
  understood, not just obeyed.
- **Agents self-verified beyond green.** Tasks 1, 3, 6, 8 ran their own
  mutation checks (disable the guard → watch the test fail → restore) without
  being asked.
- **Agents extended safely.** Task 1 closed an approve-then-raise-the-amount
  bypass unprompted; task 10 used the blessed `super()` override point the
  DSL documents.
- **The benchmark found a real product bug.** Task 2's integration test
  exposed that `assign_custom_fields!` read top-level `params[:custom_fields]`
  while the form partial nests them under the model param key — custom fields
  never persisted from any generated admin form, silently. Fixed in the gem
  template + demo with a regression test in the same change as this report.

## Caveats

- All 10 agents were the same model family as the orchestrator; no
  cross-agent comparison yet.
- Wall times are approximate (spawn-to-idle, waves of 5 sharing one machine).
- No vanilla-Rails control group yet, so the +30–50% speed target is
  unmeasured. Next run: same tasks against a bare Rails app for the baseline
  comparison OPEN_LOAM_PLAN.md calls for.
