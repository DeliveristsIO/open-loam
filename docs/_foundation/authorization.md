---
title: Authorization
description: Roles, policies, and field-level permissions — and how authorization differs from tenant isolation.
nav_order: 3
permalink: /foundation/authorization/
---

# Authorization

## Concept

Authorization answers a different question than tenant isolation. Tenancy
asks *whose* data this is; authorization asks *who, within that tenant, may
read or act on it.* A user can be a legitimate member of the right tenant and
still be denied a specific action or a specific field.

Every entity gets a `Loam::Policy` subclass, one instance per (actor, record)
pair (`lib/loam/policy.rb`). A role comes from `Loam::Membership` — the
actor's role *in the current tenant* — and default action checks
(`read?`/`create?`/`update?`/`destroy?`) mean "any member of the tenant":

```ruby
class EquipmentPolicy < Loam::Policy
  field :daily_rate, writable: [:manager]
end
```

That one line is enough to say: any member can read and create Equipment
records, but only a `:manager` may write `daily_rate`. Fields with no
declared rule are writable/readable by any member; a declared `writable:`
or `readable:` list restricts to those roles.

## Example

```ruby
policy = EquipmentPolicy.for(equipment)   # actor = Loam::Current.actor

policy.update?                # true  — any member
policy.writable?(:daily_rate) # false — actor's role isn't :manager
policy.writable?(:name)       # true  — no rule declared, any member

policy.permitted_fields(params[:equipment].keys)
# => only the field names this actor may actually write
```

`Policy.for(record)` (`lib/loam/policy.rb`) resolves `#{record.class}Policy`
by convention — no manual wiring per controller. A controller builds the
permit list from `policy.permitted_fields(...)` instead of a hand-rolled
`params.permit(...)` list, so a new writable-field rule takes effect without
touching the controller.

## Failure mode

An action a role isn't allowed to perform raises `Loam::NotAuthorizedError` —
raised by admin controllers when a policy check fails, and by a
`Loam::Workflow` transition gated with `roles:` when the current actor's role
isn't on that list (`lib/loam/errors.rb`). It is not silently ignored and it
is not a 200 with a no-op.

A read-side analog exists for custom fields: filtering or sorting the admin
index on a `Loam::FieldDefinition` the current role may not read raises
`Loam::FieldAccessError` (a subclass of `NotAuthorizedError`) — otherwise a
filter could be used as an inference oracle on a value the role can't
actually see.

## Why Loam behaves this way

**Tenancy and authorization solve different problems, and Loam keeps them
structurally separate on purpose.** Tenancy is enforced by `default_scope` on
every query — it can't be bypassed per-controller. Authorization is enforced
by explicit policy checks at the point of action — because *who may act* is
business logic that legitimately varies per entity, per field, per role, and
Loam doesn't try to guess it. Collapsing the two (e.g., "any tenant member can
do anything") is a common shortcut that a vanilla Rails app takes under time
pressure; Loam makes the field-level rule a one-line declaration instead of a
`before_action` a developer has to remember to add to every controller.

The [golden-tasks control run]({% link _agents/golden-tasks.md %}) measured
this directly: across ten agent-implemented tasks with a real authenticated
role gate applicable, Loam apps enforced it 4/4; hand-rolled vanilla-Rails
apps given the identical prompts enforced it 1/4.

## Agent guidance

- Every controller action checks a policy (`authorize!`); every form builds
  its permit list from `policy.permitted_fields`, never a hand-rolled
  `params.permit` list.
- Declare a field rule with `field :name, writable: [...], readable: [...]`
  in the entity's policy class — don't branch on `Loam.actor.role` inline in
  a model or controller.
- Feature-string permissions (`Loam::Permissions`, configured in the
  initializer — `role :manager, allow: %w[equipment.* billing.read]`) are a
  **separate, orthogonal layer**: a coarser, wildcard-aware capability check
  (`Loam.can?("equipment.edit")`, `require_permission!` in a controller) for
  gating a whole feature area rather than a single field. Roles
  (`Loam::Membership`), field policies (`Loam::Policy`), and feature
  permissions (`Loam::Permissions`) are three distinct, composable
  mechanisms — don't collapse them into one ad hoc check.
- Feature *flags* (`Loam::Features`) are a fourth, different thing again: a
  flag gates a **capability being on for a tenant at all**, independent of
  who's signed in. Don't reach for a flag when the real question is "who may
  do this."

## Related pages

- [Tenant isolation]({% link _foundation/tenant-isolation.md %}) — the
  orthogonal *whose data* question.
- [Guardrails]({% link _agents/guardrails.md %})
- [Golden tasks]({% link _agents/golden-tasks.md %}) — the measured
  role-gate comparison.
- [Pillar implementation reference]({% link _reference/pillars.md %}) —
  authorization's roadmap target (wrapping `pundit`).
