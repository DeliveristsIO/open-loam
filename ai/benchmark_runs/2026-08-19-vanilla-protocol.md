# Control-run protocol — vanilla Rails vs OpenLoam (pre-registered)

Committed BEFORE any control agent runs. Scoring rules below are frozen for
this run; deviations must be reported as deviations.

## What is being measured

Agent-vs-agent, same model family both sides: the 10 golden tasks
(as adapted in [2026-08-19-claude-fable.md](2026-08-19-claude-fable.md)),
requirements VERBATIM — branch offices, roles, notifications included — against
two baselines. This is NOT the plan's "vanilla Rails human estimate"; label it
as the AI-vs-AI control.

## Baselines (asymmetry is the thesis, disclosed not equalized)

- **OpenLoam side** (already run): fresh app + `open_loam:install` (tenancy, roles,
  policies, audit, events, notifications, API auth, webhooks, admin) +
  Company + PurchaseOrder entities + workflow. AGENTS.md is the contract.
- **Vanilla side**: `rails new` (same skip flags minus OpenLoam, plus
  `--skip-system-test`) + `rails g scaffold Company name industry` +
  `rails g scaffold PurchaseOrder supplier amount:decimal status` + green
  suite. **No User, no auth, no tenancy, no conventions doc.** Each agent
  models "branch office", "manager/employee", notifications, API security
  itself — that rebuilding cost, paid per task, is the foundation tax being
  measured.

## Prompt shape (identical apart from the contract line)

Same as the OpenLoam run: app path + verbatim business requirement + definition of
done (`bin/rails test` fully green, work only inside the app dir, report files
+ commands + final summary line). The OpenLoam line "read AGENTS.md, it is the
contract" becomes "read the app first and follow standard Rails conventions".
No hints, no human intervention; waves of 5; wall time = spawn-to-idle
(approximate, stated as such).

## Scoring (applied identically to BOTH sides' apps)

1. **Suite**: full `bin/rails test` re-run by the orchestrator from a clean
   shell. Agent-authored tests prove self-consistency only — the discriminating
   metric is the external audit:
2. **Behavioral probes**, fired by the orchestrator through each app's own
   HTTP/API surface:
   - **Isolation**: create data as branch A, attempt to read it as a branch B
     user through the app's own paths. Visible = defect. No branch concept
     built at all = defect ("isolation absent"), not N/A.
   - **Role gate**: employee attempts the manager-only action via direct HTTP
     (hidden UI buttons don't count).
   - **API auth**: unauthenticated request to any endpoint the agent built
     must be rejected.
   - **End-to-end truth**: the requested feature demonstrably works once
     through the real path.
   - **Test integrity**: baseline tests not weakened or deleted.
3. **Violations** (OpenLoam side only, as before): `.unscoped`, hand-created
   entity files, direct workflow-column writes.

## Honesty rules

- Per-task results reported even where vanilla wins (some tasks are plainly
  cheaper without runtime-field machinery); a clean sweep would be suspect.
- Caveats carried over: same model both sides, agent-authored tests,
  approximate wall times, one machine shared by concurrent agents.
- The OpenLoam-side apps get the SAME probes retroactively; their earlier
  verification (suite + grep) is superseded by this stricter audit in the
  final side-by-side table.
