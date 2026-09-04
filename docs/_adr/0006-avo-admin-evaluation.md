---
title: Evaluating Avo as an Alternate Admin Backend
description: Why the generated admin stays the default and Avo remains an app-level option.
nav_order: 6
---

# 0006. Evaluating Avo as an alternate admin backend

- Status: Accepted
- Date: 2026-08

## Context

ADR [0003]({% link _adr/0003-generated-erb-admin.md %}) chose a **generated ERB admin** over an
admin framework, deferring an Avo evaluation to this spike. The
question: should OpenLoam's admin be (re)built on [Avo](https://avohq.io), or stay
generated ERB?

What OpenLoam's admin must preserve, whichever way it goes — these are the
non-negotiables the current admin enforces structurally:

- **Tenancy**: every screen runs inside `OpenLoam::Current.tenant`; a query with no
  tenant raises. No screen may read across tenants.
- **Field-level policy**: `OpenLoam::Policy` decides per-role which fields are
  writable/readable; the permit list comes from the policy, not the form.
- **The full OpenLoam surface**: custom fields, saved views (perspectives), bulk
  actions, soft-delete + recycle bin, optimistic-lock conflict UI, comments,
  attachments, encryption-aware export, the approval gate, history/undo.
- **Agent-legibility**: an agent adds an entity with one generator and gets its
  admin for free, as plain reviewable Rails.

## What Avo brings

- A mature, batteries-included resource DSL (fields, filters, actions, cards),
  far richer out of the box than the generated screens.
- Association UIs, a polished look, search, and a large feature set maintained by
  a dedicated team — less admin code for OpenLoam to own.
- A declarative `Avo::Resource` per model that reads cleanly.

## What it costs against the non-negotiables

1. **Tenancy is not free.** Avo resolves and renders records through its own
   controllers; every resource query, association loader, and action must be
   forced through `OpenLoam.as_tenant`. That is a wrapper around Avo's request cycle
   (an `around_action` + scoped `query`/`find`), and any Avo path we forget is a
   cross-tenant leak — exactly the class of bug OpenLoam exists to make structurally
   impossible. The guardrail lint (`.unscoped` in `app/`) does not see inside a
   gem.
2. **Field-level policy is a re-implementation.** Avo has its own authorization
   (Pundit-style `*_policy`) and per-field `visible`/`readonly` — none of it
   speaks `OpenLoam::Policy`. Every field on every resource would restate the rule,
   or we bridge Avo's hooks to `OpenLoam::Policy` and keep them in sync. Two sources
   of truth for "who may write this field" is precisely the drift OpenLoam removed.
3. **The OpenLoam surface would be rebuilt in Avo's idioms.** Custom fields, saved
   views, the conflict/lock UI, the approval gate, history/undo, encryption-aware
   export — each is currently wired through the generated screens; each becomes
   an Avo field type / action / card to author and test again.
4. **Agent-legibility shifts.** "Add an entity → get its admin" would mean
   generating an `Avo::Resource` instead of ERB — learnable, but now the agent
   must know Avo's DSL and its interaction with the OpenLoam guarantees, a larger
   surface than plain Rails.
5. **A heavy dependency** for the core, whose upgrades we would track and whose
   internals we would wrap at exactly the tenancy boundary that matters most.

## Decision

**Keep the generated ERB admin as OpenLoam's core admin. Do not adopt Avo as the
backend.** The generated admin's value is that tenancy and field-policy are
enforced *structurally, in OpenLoam's own code*, and the whole OpenLoam surface composes
there by construction. Avo would move that enforcement into wrappers around a
third party at the highest-risk boundary, and re-implement the surface in its
idioms — a large cost against OpenLoam's core promise, for polish OpenLoam can add
incrementally itself.

Avo stays a **documented, app-level option**, not the core: an app that prefers
Avo can mount it for its own resources, provided it forces `OpenLoam.as_tenant`
around Avo's request cycle and bridges Avo authorization to `OpenLoam::Policy`. OpenLoam
neither ships nor blocks that.

## Consequences

- OpenLoam keeps owning its admin code and its look — the incremental polish path
  (shared stylesheet, richer filters/widgets) continues.
- No new core dependency; tenancy/policy stay enforced in first-party code.
- Teams that want Avo's richness for non-core screens can add it deliberately,
  eyes open to the two integration points above.
- Revisit if the generated admin's maintenance cost outgrows the isolation
  benefit, or if Avo ships first-class multi-tenant + external-policy hooks that
  remove integration points 1 and 2.
