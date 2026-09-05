---
title: Resolving the Proven-Gem Swaps
description: Why tenancy and audit stay in-gem for good, and why the event gap was closed in-gem rather than by adopting Rails Event Store.
nav_order: 7
---

# 0007. Resolving the proven-gem swaps

- Status: Accepted
- Date: 2026-09
- Supersedes the open question left by [0002](0002-in-gem-implementations.md)

## Context
ADR 0002 shipped minimal in-gem implementations first and left the door open:
"swapping a proven gem back in *behind the same convention* is a later refactor,
not a reversal." Four roadmap items carried that debt — wrap `acts_as_tenant`
(L-201), Pundit (L-202), `paper_trail` (L-203), and Rails Event Store (L-204).

Deferred is not decided. Read one at a time against the code as it now stands,
three of the four turn out not to be worth doing, and the fourth turns out to be
a real gap that the gem it named would not be the best way to close. Leaving them
open as perpetual "someday" items misrepresents the roadmap, so they are decided
here.

## Decision

**Tenancy stays in-gem (L-201, declined).** `OpenLoam::TenantRecord` is 36 lines
and is the tenancy security boundary the whole guardrail suite exists to test.
`acts_as_tenant` maintains its own `ActsAsTenant.current_tenant`, while
`OpenLoam::Current` is already the single context that audit, events, policy and
encryption all read. Adopting it means two current-tenant stores bridged against
each other — new failure modes across the boundary least able to afford them, for
no capability gained.

**Audit stays in-gem (L-203, declined).** `paper_trail`'s headline feature is
reify, and undo already shipped in-gem (L-704, `OpenLoam::Undo`). More decisively,
`paper_trail` serializes full `object`/`object_changes` into its versions table,
while `OpenLoam::Auditable` deliberately redacts encrypted columns to
`"[encrypted]"` and drops the blind-index sibling — because a stored ciphertext
still leaks length and, over time, correlations. Adopting it would mean
reimplementing that redaction inside someone else's serializer, one
misconfiguration away from writing encrypted values to a queryable table. That is
a security regression bought for a feature already present.

**Authorization stays in-gem, but the gap it exposed is real (L-202, declined as
a swap).** `policy_for` and `authorize!` in the generated base controllers are
already Pundit's `authorize` in six lines, and every generated action calls them.
What Pundit has that OpenLoam lacks is `verify_authorized` — the after-action
guard that fails a request whose action never authorized anything. That hole is
worth closing; it is about ten lines in-gem, and does not justify the dependency.

**Event capture closed in-gem (L-204, reframed).** The stated premise — "no
history" — was half stale: L-706 made *delivery* durable. But its own contract
says durability is of delivery, not capture, so nothing recorded that an event
happened and no stream could be replayed. That is a genuine capability gap, and
it is now closed by `OpenLoam::EventLog` + `OpenLoam::EventRecord`: every publish
is captured as an append-only, tenant-scoped row, readable and replayable by
event name or domain prefix, pruned on a retention window. Rails Event Store
would have brought its own schema, serialization and aggregate-root opinions to
do what roughly a hundred lines does against conventions the gem already has.

## Consequences
- The `OpenLoam::` contracts remain the public surface, unchanged; what changes is
  that three of them are now settled rather than provisional.
- ADR 0002's general principle still holds for anything new. This ADR resolves
  the four specific items it named, and does not license re-opening them without
  new evidence — a concrete requirement the in-gem version cannot meet.
- Capture is ON by default and captures everything except a declared exclusion.
  The comparable default-OFF switch, `OpenLoam.broadcast_events`, governs
  *exposure* (events leaving for a browser); this is internal tenant-scoped
  history, the same posture as audit-by-default. An opt-in log is a log nobody
  turns on.
- Capture runs inline in the publisher's thread, so a failed insert propagates
  into the operation that published. Deliberate: a log that silently drops
  entries is not a log.
- The event log grows with event volume. Retention (`OpenLoam.event_log_retention`,
  90 days by default) and a per-tenant daily prune are part of the feature, not a
  follow-up.
- One item remains open from this reading: the `verify_authorized`-equivalent
  guard, tracked as its own issue rather than as a Pundit swap.
