---
title: The agent contract
description: What AGENTS.md is, what a coding agent should read first, and the invariants it commits to.
nav_order: 1
permalink: /agents/agent-contract/
---

# The agent contract

## What AGENTS.md is

`open_loam:install` writes an `AGENTS.md` to every generated app's root
(from [the shipped template](https://github.com/DeliveristsIO/open-loam/blob/main/lib/generators/open_loam/install/templates/AGENTS.md)).
It's the map a coding agent (or a human) reads before making any change: where
each kind of thing lives, the one generator that adds it, and the invariants
that must not break. It opens with the framing the rest of the contract
follows from:

> This app is built on OpenLoam: a Rails foundation where tenancy, permissions,
> audit, events, and admin are already decided. There is ONE way to do each
> thing. Follow it and your change is small, reviewable, and safe. Improvise
> and the guardrail tests will fail.

## Byte-budgeted, on purpose

`AGENTS.md` is capped at 32 KB — enforced by a
[guardrail test]({% link _agents/guardrails.md %}), not just a style
preference. Agent harnesses read instruction files into a context window and
truncate what doesn't fit — **silently**. An oversized file doesn't warn; it
just loses its tail, and the tail is where the invariants and the definition
of done live. So `AGENTS.md` stays a dense reference table plus a short list
of rules, and everything else — subsystem deep-dives with real code, the
[golden-tasks methodology]({% link _agents/golden-tasks.md %}), architecture
diagrams — lives in `docs/` and is linked out to, never inlined.

## What it commits an agent to

Three things, in order of how often they matter:

1. **The map.** A table of every feature (business entity, permissions,
   admin screen, domain events, MCP server, undo, encryption, workflow,
   scheduler, dictionaries, and everything else OpenLoam ships) — where it lives
   and how to add one. Reading this table before writing code is how an
   agent avoids reinventing something OpenLoam already provides.
2. **"The one way to add a feature."** Run the entity generator — never
   hand-create entity files. Declare permissions in the generated policy.
   Publish business events explicitly. Run the full test suite, including
   the generated isolation tests, before finishing.
3. **Invariants you must not break** — the load-bearing rules: every business
   model inherits `OpenLoam::TenantRecord`; never `.unscoped` a tenant-scoped
   model; never rescue `OpenLoam::MissingTenantError` or
   `OpenLoam::UnknownCustomFieldError`; every controller action checks a policy;
   event names are `domain.thing.happened`; `OpenLoam.on_tenant_created`
   callbacks must be idempotent; delete with `soft_delete`, not `destroy`;
   never log, search, or hand-roll crypto for an encrypted field.

## What "done" means

The contract's own definition: `bin/rails test` fully green, `bin/rails
db:migrate` clean, no `.unscoped`, no new model outside the generator
convention, a policy declared for every new entity, and a diff small enough
that a human reviews it in minutes.

## Where to go deeper

`AGENTS.md`'s table links out to a subsystem page whenever the one-line
summary isn't enough — encryption, SSO, the scheduler, MCP, confirm-mode, and
the rest are in the [agent deep-dives]({% link _agents/index.md %}). The
foundation-level *why* — tenant isolation, authorization, audit — is in
[Foundation]({% link _foundation/overview.md %}).

## Related pages

- [Guardrails]({% link _agents/guardrails.md %}) — how the invariants above
  are enforced as tests, not just prose.
- [Golden tasks]({% link _agents/golden-tasks.md %}) — how well an agent
  following this contract actually does.
- [Generators]({% link _reference/generators.md %})
