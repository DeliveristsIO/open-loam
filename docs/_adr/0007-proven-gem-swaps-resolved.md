---
title: Resolving the Proven-Gem Swaps
description: Why tenancy, audit and authorization stay in-gem, and why the event gap was closed in-gem rather than with Rails Event Store.
nav_order: 7
---

# 0007. Resolving the proven-gem swaps

- Status: Accepted
- Date: 2026-09
- Resolves the open question left by [0002]({% link _adr/0002-in-gem-implementations.md %})

## Context
0002 shipped in-gem implementations first and called swapping proven gems back in
"a later refactor, not a reversal", leaving four roadmap items open: L-201
`acts_as_tenant`, L-202 Pundit, L-203 `paper_trail`, L-204 Rails Event Store.
Deferred is not decided. Read against the code as it now stands, three are not
worth doing and the fourth is a real gap the named gem is the wrong way to close.

## Decision
**Tenancy stays in-gem** (L-201). `TenantRecord` is 36 lines and is the security
boundary the guardrail suite exists to test. `acts_as_tenant` keeps its own
`current_tenant`, so adopting it means two context stores bridged against
`OpenLoam::Current` — which audit, events, policy and encryption all read.

**Audit stays in-gem** (L-203). `paper_trail` serializes full `object_changes`,
where `Auditable` deliberately redacts encrypted columns and drops the
blind-index sibling, because a stored ciphertext still leaks length and, over
time, correlations. Its headline feature, reify, already shipped as
`OpenLoam::Undo` (L-704).

**Authorization stays in-gem** (L-202). `policy_for`/`authorize!` are already
Pundit's `authorize` in six lines, and the field-level DSL is not a Pundit
feature. Its one real advantage — `verify_authorized`, which fails an action that
never authorized anything — is ~10 lines in-gem, and is tracked separately.

**Event capture closed in-gem** (L-204). Delivery was durable (L-706); capture was
not, so nothing recorded that an event happened and no stream could be replayed.
`OpenLoam::EventLog` closes it. Rails Event Store would bring its own schema,
serialization and aggregate-root opinions for the same result.

## Consequences
- No public `OpenLoam::` contract changed; three of them are now settled rather
  than provisional.
- 0002's principle still governs anything new. Re-opening one of these four needs
  a requirement the in-gem version demonstrably cannot meet.
- Capture is on by default and runs inline, so a failed insert fails the
  publishing operation. That inverts `broadcast_events`, which is opt-in because
  it governs exposure rather than internal history.
- One item stays open: the `verify_authorized`-equivalent guard.
