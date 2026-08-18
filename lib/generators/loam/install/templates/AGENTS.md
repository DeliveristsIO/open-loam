# AGENTS.md — how to extend this Loam app

This app is built on [Loam](https://github.com/DeliveristsIO/loam): a Rails
foundation where tenancy, permissions, audit, events, and admin are already
decided. There is ONE way to do each thing. Follow it and your change is small,
reviewable, and safe. Improvise and the guardrail tests will fail.

## The map

| Thing | Lives in | Added by |
|-------|----------|----------|
| Business entity | `app/models/<name>.rb` | `bin/rails g loam:entity Name field:type ... --domain <domain>` |
| Permissions | `app/policies/<name>_policy.rb` | generated with the entity; edit to declare rules |
| Admin screen | `app/controllers/admin/` + `app/views/admin/` | generated with the entity |
| Domain events | published from models/services via `Loam::Events.publish` | subscriptions in `config/initializers/loam.rb` |
| Audit trail | automatic (`Loam::Auditable`) | nothing — it is on by default |
| Migration-free field | `custom_fields` jsonb column, read/written via `Loam::CustomFields` | a `Loam::FieldDefinition` row, created via the admin "Field definitions" screen (`/admin/field_definitions`) — never a migration |
| States & approvals | a `workflow` block in the model (`Loam::Workflow`) | `include Loam::Workflow`; add a string column for the state |
| Tests | `test/entities/<name>_test.rb` | generated with the entity; extend, never delete |
| New-tenant defaults | `Loam.on_tenant_created` blocks in `config/initializers/loam.rb` | edit the initializer; backfill with `bin/rails loam:sync` |

## The one way to add a feature

1. Run the generator — never hand-create entity files:
   `bin/rails g loam:entity DamageReport reservation_id:integer description:text approved:boolean --domain rental`
2. `bin/rails db:migrate`
3. Declare permissions in the generated policy, e.g.:
   `field :approved, writable: [:manager]`
4. Add business logic to the model; publish business events explicitly:
   `Loam::Events.publish("billing.penalty.due", id: id)`
5. Run `bin/rails test`. All green — including the generated isolation tests — before you finish.

## Adding a field with no migration

If a field doesn't need a real column — an admin-configurable attribute, a
one-off value, something that varies per tenant — don't run the entity
generator again. Create a `Loam::FieldDefinition` instead (`entity_type`,
`name`, `field_type`, optional `writable_roles`), typically via the admin
"Field definitions" screen. Every generated entity already has a
`custom_fields` jsonb column and `include Loam::CustomFields`, so the field is
immediately readable/writable via `record.custom_field(:name)` /
`record.set_custom_field(:name, value)` and renders on the generated admin
form/show screens automatically. Reading or writing a name with no matching
`Loam::FieldDefinition` raises `Loam::UnknownCustomFieldError` — that means
the field definition doesn't exist yet, not that you should rescue it.

## States and approvals

A record that moves through stages — draft → pending → approved — declares a
workflow instead of hand-rolled `if status ==` checks. Add a string column for
the state, then:

```ruby
include Loam::Workflow

workflow :status, initial: "draft" do
  state "draft"; state "pending_approval"; state "approved"
  transition :submit,  from: "draft",            to: "pending_approval"
  transition :approve, from: "pending_approval", to: "approved", roles: [:manager]
end
```

`order.submit!` moves the record, saves it, and publishes
`<domain>.<entity>.submit` with `from`/`to`; an illegal move raises
`Loam::InvalidTransitionError` and a `roles:`-gated one raises
`Loam::NotAuthorizedError`. `order.workflow_transitions_available` lists what
this actor may do next, and `Model.loam_workflow` is the whole machine, frozen
and readable.

## Seeding a new tenant

Anything every tenant should start with — roles, default field definitions,
starter records — belongs in a `Loam.on_tenant_created` block in
`config/initializers/loam.rb`, never in a one-off script. The block runs inside
`Loam.as_tenant(tenant)` when the tenant is created, and again for every
existing tenant when someone runs `bin/rails loam:sync`. That second path is
the point: it is how a default you add today reaches tenants created last year.
So the block MUST be idempotent — `find_or_create_by!`, never `create!`.

## Invariants you MUST NOT break

- **Every business model inherits `Loam::TenantRecord`.** Never `ApplicationRecord`
  for domain data. The guardrail test `test/loam_guardrails_test.rb` fails otherwise.
- **Never call `.unscoped` on a tenant-scoped model.** It is the only way to see
  other tenants' data and it is reserved for vetted framework code.
- **Never rescue `Loam::MissingTenantError`.** It firing means a bug upstream —
  fix the missing `Loam.as_tenant` context instead.
- **Never rescue `Loam::UnknownCustomFieldError`.** It firing means the
  `Loam::FieldDefinition` doesn't exist — create it, don't swallow the error.
- **Never write raw SQL that touches tenant tables** without a `tenant_id` predicate.
- **Every controller action checks a policy** (`authorize!`); every form uses
  `policy.permitted_fields` — no hand-rolled `params.permit` lists.
- **Event names are `domain.thing.happened`** — three+ dot-separated segments.
- **`Loam.on_tenant_created` callbacks are idempotent** — `loam:sync` re-runs them.
- **Never assign a workflow column directly** — call the transition, so the legal
  moves and the roles that may make them stay in one place.

## Context helpers

- `Loam.as_tenant(tenant, actor: user) { ... }` — run code as a tenant/actor.
- `Loam.tenant!` — current tenant or raise. `Loam.actor` — current user.
- In tests: `with_tenant(tenant, actor: user) { ... }`.

## Definition of done

`bin/rails test` fully green, `bin/rails db:migrate` clean, no `.unscoped`,
no new model outside the generator convention, policy declared for every new
entity, and the diff small enough that a human reviews it in minutes.

*This file is budgeted: ≤ 32 KB, enforced by `test/loam_guardrails_test.rb`.
Agent harnesses truncate oversized instruction files without warning, so
everything past the budget stops being read. Link out to `docs/` instead of
growing this file.*
