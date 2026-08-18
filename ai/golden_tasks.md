# Loam Golden AI Tasks

The permanent benchmark from [LOAM_PLAN.md](../LOAM_PLAN.md) (Days 31–45).
Each task is given to a coding agent against a fresh Loam app (the generator
harness knows how to build one — see `test/`). The agent gets AGENTS.md and the
task text, nothing else. Run repeatedly; a task counts as passed only when the
full suite (including guardrails) is green and no invariant was violated.

## Tasks

| # | Task | Exercises |
|---|------|-----------|
| 1 | Add approval for purchase orders above €10,000. | workflow, policy, events |
| 2 | Add a custom field to Company. | custom fields, admin |
| 3 | Create a new permission (only managers may export contacts). | policy, field rules |
| 4 | Add a dashboard metric (open orders per tenant). | admin, tenancy |
| 5 | Create a webhook on order status change. | webhooks, events |
| 6 | Add a REST endpoint (approved orders). | API, policy |
| 7 | Add a scheduled job (daily overdue-rental digest). | jobs, tenancy |
| 8 | Add a notification (notify manager on damage report). | notifications, subscribers |
| 9 | Add a workflow state (suspended) to an existing flow. | workflow |
| 10 | Modify an existing workflow (approval threshold €5,000). | workflow, tests |

## Metrics per run

| Metric | Initial target |
|---|---:|
| Task completed | > 90% |
| Tests passing | > 95% |
| Architecture violations (guardrail failures, `.unscoped`, hand-created entity files) | < 5% |
| Human interventions | decreasing |
| Time vs vanilla Rails baseline | +30–50% faster |

Record results per run in `ai/benchmark_runs/` as dated markdown files
(`YYYY-MM-DD-<agent>.md`): task, outcome, violations, interventions, wall time.
Do not market speed claims until there are enough real measurements
(LOAM_PLAN.md, "Loam AI Benchmark").
