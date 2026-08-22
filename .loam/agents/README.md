# The Loam agent pack (L-301)

Everything an AI coding agent needs to extend a Loam app **correctly** —
assembled in one place so a harness (Claude Code, Cursor, Codex, an SDK agent)
can load it as a unit. Loam is designed to be *agent-legible*: there is one way
to do each thing, the invariants are enforced by tests, and this pack points at
each piece.

## Load order (what an agent should read, in order)

1. **`AGENTS.md`** (at the app root) — the contract: the map of where things
   live, the one way to add each (always the generators), and the invariants that
   must not break (tenancy, authorization). Byte-budgeted (≤32 KB) so it loads in
   full. This is the single most important file.
2. **[`ai/lessons.md`](../../ai/lessons.md)** — real gotchas found the hard way in
   this codebase, as claim + rule. Read before a non-trivial change.
3. **[`docs/adr/`](../../docs/adr/)** — why the architecture is the way it is, and
   the specs-as-ADRs convention: record a substantial decision as an ADR before
   implementing.
4. **[`docs/agents/`](../../docs/agents/)** — deep-dives on the subsystems that
   have sharp edges (encryption, SSO, scheduler, events, inbound webhooks, undo,
   bulk import/export, confirm-mode). Linked from `AGENTS.md` per topic.
5. **[`BACKWARD_COMPATIBILITY.md`](../../BACKWARD_COMPATIBILITY.md)** — the frozen
   public surfaces. Don't change these without the deprecation dance.

## The one rule that matters most

**Add features through the generators, not free-form.** `rails g loam:entity Name
field:type …` scaffolds a tenant-scoped, audited, evented entity with its admin,
API, and policy — every invariant wired in. Editing generated code is fine;
hand-rolling a model that skips `Loam::TenantRecord`, or a controller that skips
the policy, is what the guardrail tests catch.

## Proving an agent works: the benchmark

- **[`ai/golden_tasks.md`](../../ai/golden_tasks.md)** — the permanent task suite.
  Each task is given to an agent against a *fresh* Loam app (the generator harness
  in `test/` builds one) with only `AGENTS.md` and the task text. A task passes
  only when the full suite (including guardrails) is green and no invariant was
  violated.
- **[`ai/benchmark_runs/`](../../ai/benchmark_runs/)** — recorded runs with
  metrics (completion, test-pass rate, violations, interventions), plus the
  vanilla-Rails control for comparison.

## What "correct" is measured against

Every change must keep these true — they are structural, so a violation shows up
as a failing test, not a subtle bug:

- **Tenancy**: no query, job, or event crosses a tenant; a missing tenant context
  raises. A lint bans `.unscoped` in `app/`.
- **Authorization**: field-level writes go through `Loam::Policy`; the permit list
  comes from the policy, never the form.
- **Auditability**: changes are recorded; encrypted values never leak into the
  audit.

## Manifest

| Piece | Path | Role |
|---|---|---|
| Contract | `AGENTS.md` (app root) | the map + invariants |
| Lessons | `ai/lessons.md` | gotchas, claim+rule |
| Decisions | `docs/adr/` | why + the ADR convention |
| Deep-dives | `docs/agents/` | subsystem sharp edges |
| Contracts | `BACKWARD_COMPATIBILITY.md` | frozen surfaces |
| Benchmark | `ai/golden_tasks.md`, `ai/benchmark_runs/` | prove it |
