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

Every entity gets a `OpenLoam::Policy` subclass, one instance per (actor, record)
pair (`lib/open_loam/policy.rb`). A role comes from `OpenLoam::Membership` — the
actor's role *in the current tenant* — and default action checks
(`read?`/`create?`/`update?`/`destroy?`) mean "any member of the tenant":

```ruby
class EquipmentPolicy < OpenLoam::Policy
  field :daily_rate, writable: [:manager]
end
```

That one line is enough to say: any member can read and create Equipment
records, but only a `:manager` may write `daily_rate`. Fields with no
declared rule are writable/readable by any member; a declared `writable:`
or `readable:` list restricts to those roles.

## Example

```ruby
policy = EquipmentPolicy.for(equipment)   # actor = OpenLoam::Current.actor

policy.update?                # true  — any member
policy.writable?(:daily_rate) # false — actor's role isn't :manager
policy.writable?(:name)       # true  — no rule declared, any member

policy.permitted_fields(params[:equipment].keys)
# => only the field names this actor may actually write
```

`Policy.for(record)` (`lib/open_loam/policy.rb`) resolves `#{record.class}Policy`
by convention — no manual wiring per controller. A controller builds the
permit list from `policy.permitted_fields(...)` instead of a hand-rolled
`params.permit(...)` list, so a new writable-field rule takes effect without
touching the controller.

## Failure mode

An action a role isn't allowed to perform raises `OpenLoam::NotAuthorizedError` —
raised by admin controllers when a policy check fails, and by a
`OpenLoam::Workflow` transition gated with `roles:` when the current actor's role
isn't on that list (`lib/open_loam/errors.rb`). It is not silently ignored and it
is not a 200 with a no-op.

A read-side analog exists for custom fields: filtering or sorting the admin
index on a `OpenLoam::FieldDefinition` the current role may not read raises
`OpenLoam::FieldAccessError` (a subclass of `NotAuthorizedError`) — otherwise a
filter could be used as an inference oracle on a value the role can't
actually see.

## Why OpenLoam behaves this way

**Tenancy and authorization solve different problems, and OpenLoam keeps them
structurally separate on purpose.** Tenancy is enforced by `default_scope` on
every query — it can't be bypassed per-controller. Authorization is enforced
by explicit policy checks at the point of action — because *who may act* is
business logic that legitimately varies per entity, per field, per role, and
OpenLoam doesn't try to guess it. Collapsing the two (e.g., "any tenant member can
do anything") is a common shortcut that a vanilla Rails app takes under time
pressure; OpenLoam makes the field-level rule a one-line declaration instead of a
`before_action` a developer has to remember to add to every controller.

The [golden-tasks control run]({% link _agents/golden-tasks.md %}) measured
this directly: across ten agent-implemented tasks with a real authenticated
role gate applicable, OpenLoam apps enforced it 4/4; hand-rolled vanilla-Rails
apps given the identical prompts enforced it 1/4.

## Agent guidance

- Every controller action checks a policy (`authorize!`); every form builds
  its permit list from `policy.permitted_fields`, never a hand-rolled
  `params.permit` list.
- Declare a field rule with `field :name, writable: [...], readable: [...]`
  in the entity's policy class — don't branch on `OpenLoam.actor.role` inline in
  a model or controller.
- Feature-string permissions (`OpenLoam::Permissions`, configured in the
  initializer — `role :manager, allow: %w[equipment.* billing.read]`) are a
  **separate, orthogonal layer**: a coarser, wildcard-aware capability check
  (`OpenLoam.can?("equipment.edit")`, `require_permission!` in a controller) for
  gating a whole feature area rather than a single field. Roles
  (`OpenLoam::Membership`), field policies (`OpenLoam::Policy`), and feature
  permissions (`OpenLoam::Permissions`) are three distinct, composable
  mechanisms — don't collapse them into one ad hoc check.
- Feature *flags* (`OpenLoam::Features`) are a fourth, different thing again: a
  flag gates a **capability being on for a tenant at all**, independent of
  who's signed in. Don't reach for a flag when the real question is "who may
  do this."

## The authorization-called guard

Forgetting `authorize!` is otherwise silent: the action renders and nothing says
the policy was never consulted. `verify_authorized!` runs after every admin and
API action and raises `OpenLoam::AuthorizationNotPerformedError` unless the action
called `authorize!`, `require_role!` or `require_permission!`.

A screen authorized structurally rather than by a policy call declares the
exemption, with a reason:

```ruby
class Admin::NotificationsController < Admin::BaseController
  skip_authorization! "Scoped to current_actor — there is no path to another user's notifications."
end
```

`require_feature!` and `require_sudo!` deliberately do **not** satisfy the guard:
one gates a capability and the other is step-up auth, so neither answers "may
this person do this".

It runs *after* the action, so it catches the omission in development and in
tests — a `destroy` that forgot to authorize has already run. It fails the build,
it does not stop the request.

## Related pages

- [Tenant isolation]({% link _foundation/tenant-isolation.md %}) — the
  orthogonal *whose data* question.
- [Guardrails]({% link _agents/guardrails.md %})
- [Golden tasks]({% link _agents/golden-tasks.md %}) — the measured
  role-gate comparison.
- [ADR 0007]({% link _adr/0007-proven-gem-swaps-resolved.md %}) — why
  authorization stays in-gem rather than wrapping `pundit`.
