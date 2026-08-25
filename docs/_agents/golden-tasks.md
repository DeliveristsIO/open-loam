---
title: Golden tasks
description: The benchmark methodology and the real, internal-only results measuring whether Loam changes agent behavior.
nav_order: 3
permalink: /agents/golden-tasks/
---

# Golden tasks

> The benchmark is intended to test whether Loam changes coding-agent
> behavior, not to manufacture a favorable comparison.

**These are internal benchmark runs, not independently reproduced.** Same
model family authored both the Loam and vanilla-Rails sides of the control
run described below, and the probes that scored them. Read the numbers with
that in mind — the methodology and every caveat are disclosed below and in
the source run files, not smoothed over.

## The 10 tasks

The permanent benchmark, from [`ai/golden_tasks.md`](https://github.com/DeliveristsIO/open-loam/blob/main/ai/golden_tasks.md).
Each task is given to a coding agent against a fresh app. The agent receives
`AGENTS.md` and the task text — nothing else, no hints, no human
intervention. A task counts as passed only when the full suite (including the
[guardrail]({% link _agents/guardrails.md %}) tests) is green **and** no
invariant was violated.

1. Add approval for purchase orders above €10,000.
2. Add a custom field to Company.
3. Create a new permission (only managers may export contacts).
4. Add a dashboard metric (open orders per tenant).
5. Create a webhook on order status change.
6. Add a REST endpoint (approved orders).
7. Add a scheduled job (daily overdue-rental digest).
8. Add a notification (notify manager on damage report).
9. Add a workflow state (suspended) to an existing flow.
10. Modify an existing workflow (approval threshold €5,000).

Target metrics per run: task completion > 90%, tests passing > 95%,
architecture violations < 5%, human interventions decreasing.

## Scoring

`Loam::Eval` (`lib/loam/eval.rb`) parses the suite tally from `bin/rails test`
output and applies the bar — green suite **and** no invariant violated —
into a machine-readable scorecard:

```bash
bin/rails "loam:eval[2]"                        # task 2 — tests only
bin/rails "loam:eval[2,cross-tenant read in X]"  # note an invariant breach
```

It writes the scorecard under `ai/benchmark_runs/` and exits non-zero on
failure, so it drops straight into CI. The scoring is what stays comparable
across runs — driving the agent itself is out of scope for the tool.

## Run 1: Loam alone, 10/10

From [`ai/benchmark_runs/2026-08-19-claude-fable.md`](https://github.com/DeliveristsIO/open-loam/blob/main/ai/benchmark_runs/2026-08-19-claude-fable.md).
Ten isolated copies of a fresh Loam app, one agent per copy, each given only
the app path and the task text. Every result independently re-verified from a
clean shell plus a `.unscoped` grep.

| Metric | Target | Result |
|---|---:|---:|
| Task completed | > 90% | **100% (10/10)** |
| Tests passing | > 95% | **100%** |
| Architecture violations | < 5% | **0** |
| Human interventions | decreasing | **0** |

Agents composed existing primitives rather than reinventing them — one task
recognized the existing webhook registry and closed only the real gap, wrote
no new HTTP code. Another explicitly declined to add a tenant predicate by
hand ("that would have been the bug"): structural tenancy was understood, not
just obeyed. The run also caught a real product bug — task 2's test exposed
that custom-field assignment read the wrong params key, so fields never
persisted from a generated admin form. Fixed in the same change as the report.

Caveats stated in the run itself: all ten agents were the same model family
as the orchestrator (no cross-agent comparison yet), wall times are
approximate, and this run alone had no vanilla-Rails control group.

## Run 2: Loam vs. vanilla Rails, same prompts, same model

From [`ai/benchmark_runs/2026-08-19-vanilla-control.md`](https://github.com/DeliveristsIO/open-loam/blob/main/ai/benchmark_runs/2026-08-19-vanilla-control.md),
per the [pre-registered protocol](https://github.com/DeliveristsIO/open-loam/blob/main/ai/benchmark_runs/2026-08-19-vanilla-protocol.md)
(committed before any control agent ran, so the scoring rules were frozen in
advance). Same model family built **both** sides and the behavioral probes
that scored them — this removes the "agent graded its own homework" objection
at the probe layer (an independent auditor role ran the probes), but not the
model-monoculture one. Deliberately asymmetric baselines: Loam side gets
`loam:install` (tenancy, roles, policies, audit, events, admin) before task
one; vanilla side gets `rails new` plus two scaffolds — no User, no auth, no
tenancy, no conventions doc. That asymmetry — what a real team actually
starts a project with, one way or the other — is the thing being measured.

| | Loam + AI | Vanilla + AI |
|---|---:|---:|
| Tasks with green suite | 10/10 | 10/10 |
| **Tenant isolation enforced** (HTTP probe) | **10/10** | **1/10** |
| **Real authenticated role gate** (of 4 applicable) | **4/4** | **1/4** |
| API auth enforced (of 1 applicable) | 1/1 | 1/1 |
| Feature works end-to-end | 10/10 | 10/10 |

Both sides shipped working, tested features on all ten tasks — the suites
alone don't discriminate. What separated them was a real HTTP/API behavioral
audit fired identically against both: could branch B read branch A's data
through the app's own paths, and did a manager-only action actually reject a
non-manager over direct HTTP (not just hide a button).

**Loam: 10/10 clean.** Isolation held in every app, including two that
rewrote the workflow machine and one that added a new API route. Manager
gates refused direct HTTP with 403. No agent wrote a tenant predicate by
hand — none needed to. Zero lines were removed from any generated guardrail
or entity test across all ten apps.

**Vanilla: isolation 1/10, role gate 1/4.** All ten vanilla apps — including
the one with real API-token auth — left the inherited scaffold serving every
branch's data to unauthenticated HTTP. Concretely: one task's approval
endpoint accepted an unauthenticated POST with a free-text `manager=` param
and no User model at all; another's own agent-written comment noted the
branch could be switched with a `?branch_office_id=` query parameter because
there was no sign-in yet; a third exposed `GET /users/<any-id>/notifications`
to any anonymous caller. Where a task's own acceptance criteria happened to
name security explicitly, the agent built it well — one task reached for
Rails 8's `rails g authentication` and produced a genuine role gate. The
pattern is that on vanilla, security got built **per ticket, ten
incompatible times, only when asked**; on Loam it was an app-wide property
before task one.

**Cost, honestly reported.** Vanilla was faster or equal on tasks that need
no foundation — a plain custom field is just a migration when there's no
runtime-field machinery. Several vanilla suites were larger specifically
because that agent had to build and test a workflow, a User model, and a
session layer Loam ships for free; a bigger diff there is the foundation tax
being paid per task, not a virtue.

### Caveats (carried from the run, not omitted)

- Same model family authored both sides **and** the probes.
- Wall times are approximate; concurrent agents shared one machine.
- Agent-authored suites prove self-consistency only; the behavioral probes
  are the discriminating evidence, which is why they were run identically on
  both sides.
- A third baseline — vanilla Rails built by a human, not an agent — is still
  unmeasured.

## What this does and doesn't show

It shows that, under identical prompts and the same model, an agent working
inside Loam's conventions produced tenant isolation and role gating as a
structural property in 10/10 and 4/4 apps respectively, while the same agent
starting from a bare Rails app produced them in 1/10 and 1/4 — without being
told to skip security, and in several cases while explicitly noting the gap
in its own code comments. It does not show performance across model
families, a human baseline, or results outside these ten tasks.

## Related pages

- [Guardrails]({% link _agents/guardrails.md %}) — the enforcement mechanism
  these results are measuring the effect of.
- [Tenant isolation]({% link _foundation/tenant-isolation.md %}) and
  [Authorization]({% link _foundation/authorization.md %}) — what the probes
  actually checked.
- [The agent contract]({% link _agents/agent-contract.md %})
