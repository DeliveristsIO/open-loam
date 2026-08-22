# 0004. A byte-budgeted AGENTS.md as the agent contract

- Status: Accepted
- Date: 2026-08

## Context
An AI agent extending the app needs one authoritative map: where things go, the
one way to add each, and the invariants it must not break (tenancy, authorization).
Scattering this across docs, or letting it grow unbounded, makes an agent harness
truncate or miss the tail.

## Decision
Ship a single `AGENTS.md` per app (generated), byte-budgeted to ≤ 32 KB and
enforced by a guardrail test. Deep-dives move to `docs/agents/*.md` linked from it,
so the contract stays inside the budget.

## Consequences
- The contract is one predictable file an agent always reads in full.
- Adding a feature means adding one line to `AGENTS.md` and (if needed) a
  `docs/agents/` page — a convention the templates and this repo follow.
- The budget forces prioritization; verbose material lives in the linked pages.
