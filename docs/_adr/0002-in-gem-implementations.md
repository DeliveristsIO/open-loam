---
title: In-Gem Implementations Before Wrapping Proven Gems
description: Why the prototype ships minimal in-gem implementations instead of wrapping acts_as_tenant/pundit/paper_trail first.
nav_order: 2
---

# 0002. In-gem implementations before wrapping proven gems

- Status: Accepted
- Date: 2026-08

## Context
The original plan was to wrap proven gems (`acts_as_tenant`, `pundit`,
`paper_trail`, Rails Event Store, Avo) behind Loam conventions. But the value Loam
is proving is the *fusion* — that tenancy, policy, audit, events, and encryption
all agree with each other and with the tenant boundary on day zero — and whether
an agent can extend that fusion. A pile of third-party dependencies would make
that harder to reason about and test end to end.

## Decision
Ship minimal in-gem implementations behind Loam's own public conventions first —
the smallest surface that proves the conventions and the agent flow. The `Loam::`
API is the contract; its internals are replaceable.

## Consequences
- Fewer moving parts to reason about while proving the thesis; every pillar is
  readable in one place.
- Swapping a proven gem back in *behind the same convention* is a later refactor
  (backlog L-201…L-204), not a reversal — the contract does not change.
- Some features are intentionally minimal (single-process SSE, deterministic HKDF
  keys) with the scaling seam documented, not faked.
