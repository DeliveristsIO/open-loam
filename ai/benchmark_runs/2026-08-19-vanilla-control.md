# Control run — vanilla Rails vs OpenLoam, both + AI

Run per the pre-registered [protocol](2026-08-19-vanilla-protocol.md). Same
model family authored both sides and the probes; requirements verbatim; no
hints; no human intervention. This is the **AI-vs-AI control**, not the plan's
human-estimate baseline.

## Headline

| | OpenLoam + AI | Vanilla + AI |
|---|---|---|
| Tasks with green suite | 10/10 | 10/10 |
| **Tenant isolation enforced** (HTTP probe) | **10/10** | **1/10** |
| **Real authenticated role gate** (of 4 applicable) | **4/4** | **1/4** |
| API auth enforced (of 1 applicable) | 1/1 | 1/1 |
| Feature works end-to-end | 10/10 | 10/10 |
| Test integrity (baseline tests intact) | 10/10 | 10/10 |

Both sides ship working, tested features. They diverge on the properties no
single ticket names but every business app needs: **who can see whose data, and
who is allowed to act.** On OpenLoam those hold by construction on all ten; on
vanilla they were built only where a task's acceptance criteria happened to
spell them out — and even then, only for the one endpoint named.

## The two baselines (asymmetric on purpose — that asymmetry is the measurement)

- **OpenLoam**: `open_loam:install` ships tenancy, roles, policies, audit, events,
  notifications, API auth, webhooks and an admin before task one. AGENTS.md is
  the contract.
- **Vanilla**: `rails new` + two scaffolds. No User, no auth, no tenancy, no
  conventions doc. Each agent invents "branch office", "manager", and API
  security itself, per task.

## Per-task, side by side

Wall times are approximate (spawn-to-idle, waves of five sharing one machine).
Suite counts are the agent-authored suites, re-run by the orchestrator.

| # | Task | OpenLoam suite | Vanilla suite | OpenLoam isolation / role | Vanilla isolation / role |
|---|------|-----------|---------------|-----------------------|--------------------------|
| 1 | Approval > €10k | 24/63 | 29/54 | pass / pass | **absent / fail** (approver = free-text param, no User) |
| 2 | Custom field on Company | 26/64 | 22/35 | pass / n-a | absent / n-a (plain column; faster on vanilla) |
| 3 | Manager-only CSV export | 21/68 | 35/98 | pass / pass | absent / **pass** (agent ran `rails g authentication`) |
| 4 | Dashboard metric | 21/57 | 25/51 | pass / n-a | **fail** (`?branch_office_id=` switches office, no check) |
| 5 | Webhook on status change | 28/119 | 35/74 | pass / pass | **fail** (branch=Company; unsigned; one shared list) |
| 6 | REST approved-orders | 20/48 | 21/42 | pass / n-a | **pass** (bearer token) — but HTML scaffold left open |
| 7 | Daily overdue digest | 24/68 | 25/51 | pass / pass | **fail** (job scopes right; every controller unscoped) |
| 8 | Notify managers on submit | 19/45 | 25/55 | pass / pass | **fail** (`/users/:id/notifications` leaks any inbox) |
| 9 | Suspended workflow state | 22/55 | 45/121 | pass / pass | absent / **fail** (sign-in accepts any user_id, no password) |
| 10 | Reason ≥ €5k | 24/56 | 30/67 | pass / pass | absent / **fail** (approver_id is a caller-supplied param) |

## What the behavioral audit found (both sides probed identically)

**OpenLoam — 10/10 clean.** Independent auditor fired the protocol probes through
each app's real HTTP/model paths. Isolation held in every app, including the
two that rewrote the workflow machine (1, 9) and the one that added an API
route (6). Manager gates refused direct HTTP with **403**, not just hidden
buttons (task 3 export, task 5 transition). No agent wrote a tenant predicate
by hand; none needed to. Test integrity is stronger than "not weakened":
**zero lines removed** from any generated guardrail or entity test across all
ten; suites reproduce the published counts exactly. The auditor's only two
initial failures were bugs in its own probes, disclosed and corrected.

**Vanilla — isolation enforced 1/10, role gate 1/4.** The systemic finding is
sharper than any single score: **all ten apps, the API one included, left the
inherited scaffold serving every branch's purchase orders to unauthenticated
HTTP.** Verbatim probe outputs:

- task 1: unauthenticated `POST approve` with `manager="Mallory the Intern"` →
  order approved. No User model exists.
- task 4: its own resolver comment — *"there is no sign-in yet, so the branch
  office ... can be switched with a `?branch_office_id=` parameter."* Both
  branches' secrets render to an anonymous GET.
- task 8: `GET /users/<any-id>/notifications` returns any user's inbox, another
  branch's manager included, to an anonymous caller.
- task 9: `require_manager` is real, but `POST /session` signs you in as any
  `user_id` with no password — "a gate whose key is printed on the door."
- task 6 (the good one): bearer token enforced, `?branch_office_id=` override
  ignored — but the inherited HTML scaffold still serves both branches open.

Where a vanilla task *did* name security, an agent could build it well: task 3
reached for Rails 8's `rails g authentication` and produced a genuine
authenticated role gate. The lesson isn't that the model can't do auth — it's
that on vanilla it does so **per ticket, ten incompatible times**, and only
when asked; on OpenLoam it's an app-wide property present before the first task.

## Cost side of the ledger (honest)

Vanilla was **faster or equal on the tasks that need no foundation** — task 2
(a custom field) is just a migration when there's no runtime-field machinery,
and vanilla's suite for it was smaller and quicker. Several vanilla suites are
larger (task 9: 45 tests) precisely because the agent had to build and test a
workflow, a User model, and a session layer that OpenLoam ships. Bigger diffs are
not a virtue here: they are the foundation tax, paid in bespoke, unaudited,
mutually incompatible security code — the exact surface a reviewer must now
scrutinize on every one of ten apps instead of trusting once.

## Caveats (carried from the protocol)

- Same model family authored both sides **and** the probes. This audit removes
  the "agent graded its own homework" objection at the probe layer (an
  independent auditor ran them), but not the model-monoculture one.
- Wall times approximate; concurrent agents shared one machine.
- Agent-authored suites prove self-consistency; the behavioral probes are the
  discriminating evidence, which is why they were run identically on both sides.
- One human-estimate baseline (vanilla-Rails-by-a-person) is still unmeasured;
  that is the plan's 25–50% target and a separate exercise.

## Bottom line

The thesis under test — *"AI can safely modify a OpenLoam application because OpenLoam
gives the agent strong conventions"* — now has a control. Given identical
prompts and the same model, **OpenLoam apps enforced tenant isolation 10/10 and
role gating 4/4; vanilla apps 1/10 and 1/4**, with every vanilla app leaking
data to unauthenticated HTTP. The foundation isn't what makes the feature work
— both sides got the feature working. It's what makes the feature **safe by
default when nobody told the agent to make it safe.**
