# AGENTS.md — how to extend this Loam app

This app is built on [Loam](https://github.com/DeliveristsIO/open-loam): a Rails
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
| Delete / recycle bin | soft-delete via `Loam::SoftDeletable` | `record.soft_delete` hides it (excluded by default, still tenant-scoped, audited); `Model.only_deleted` + `record.restore` bring it back; `destroy` still hard-erases |
| Settings / config | `Loam::Configs` (a `key` + JSON value, global or per-tenant) | `Loam::Configs.get("rental.currency")`; `set(k, v)` overrides for the current tenant, `set(k, v, scope: :global)` sets the app-wide row, `reset(k)` drops the override; declare defaults in the initializer; admin at `/admin/configs` |
| Feature flags | `Loam::Features` (a capability on/off per tenant, over `Loam::Configs`) | `Loam::Features.on?(:beta)`; `enable(:beta)`/`disable(:beta)` override for the current tenant, `enable(:beta, scope: :global)` app-wide, `reset(:beta)` drops it; declare in `Loam.feature_defaults`; guard via `require_feature!`/`feature_on?`; admin at `/admin/features` |
| Encryption at rest | `Loam::Encryptable` (`encrypts :field`, per-tenant AES-256-GCM) | generate with `--encrypt ssn --encrypt-searchable email`, or add `encrypts :ssn` / `encrypts :email, searchable: true` to the model; read/write is transparent, `find_by_email` matches the blind index; set `LOAM_MASTER_KEY`; NEVER `searchable_by` an encrypted field |
| Migration-free field | `custom_fields` jsonb column, read/written via `Loam::CustomFields` | a `Loam::FieldDefinition` row, created via the admin "Field definitions" screen (`/admin/field_definitions`) — never a migration |
| States & approvals | a `workflow` block in the model (`Loam::Workflow`) | `include Loam::Workflow`; add a string column for the state |
| Notifications | `Loam::Notification` rows, read at `/admin/notifications` | `Loam::Notifications.notify(user, title:)` / `notify_role(:manager, title:)`, normally from an event subscriber |
| Search | `searchable_by :col, :col` in the model (`Loam::Searchable`) | declared with the entity for its string/text columns; `Model.search(q)` and the admin's global box at `/admin/search` |
| Long lists | `paginate(scope)` from `Admin::Pagination` in `BaseController` | already wired into generated index screens — 25 a page, with a filter box |
| Comments | `Loam::Comment` rows via `Loam::Commentable` | `record.comment!("...")`, or the form on the entity's show screen; publishes `loam.comment.created` |
| Attachments | ActiveStorage `files` via `Loam::Attachable` | `record.files.attach(...)`, or the file field on the entity's form — uploading counts as an update, so the entity's policy decides |
| Sign-in | `app/controllers/admin/sessions_controller.rb` (`has_secure_password` on `User`) | email + password, then a tenant — the picker only ever lists tenants you hold a `Loam::Membership` in |
| JSON API | `app/controllers/api/<plural>_controller.rb` | generated with the entity; auth is `Authorization: Bearer <Loam::ApiToken>`, and the same policies apply |
| Webhooks | `Loam::WebhookEndpoint` rows, managed at `/admin/webhook_endpoints` | add an endpoint with an event pattern; matching events POST signed JSON via `Loam::WebhookDeliveryJob` |
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
"Field definitions" screen. Every entity already has a `custom_fields` jsonb
column and `include Loam::CustomFields`, so the field is immediately
readable/writable via `record.custom_field(:name)` /
`record.set_custom_field(:name, value)` and renders on the admin form/show
screens automatically. Reading or writing a name with no matching
`Loam::FieldDefinition` raises `Loam::UnknownCustomFieldError` — that means
the field definition doesn't exist yet, not that you should rescue it.

## States and approvals

A record that moves through stages — open → pending → approved — declares a
workflow instead of hand-rolled `if state ==` checks. `DamageReport` is the
worked example. Add a string column for the state, then:

```ruby
include Loam::Workflow

workflow :state, initial: "open" do
  state "open"; state "pending_approval"; state "approved"
  transition :submit,  from: "open",             to: "pending_approval"
  transition :approve, from: "pending_approval", to: "approved", roles: [:manager]
end
```

`report.submit!` moves the record, saves it, and publishes
`rental.damage_report.submit` with `from`/`to`; an illegal move raises
`Loam::InvalidTransitionError` and a `roles:`-gated one raises
`Loam::NotAuthorizedError`. `report.workflow_transitions_available` lists what
this actor may do next, and `Model.loam_workflow` is the whole machine, frozen
and readable.

## Deleting a record

There is ONE way to delete a business record: `record.soft_delete` (the admin
delete button and the JSON `DELETE` already call it). It sets `deleted_at`, so
the record is hidden from every ordinary query — excluded by default, never a
filter you must remember. It stays tenant-scoped in the recycle bin
(`Model.only_deleted`, `Model.with_deleted`), `record.restore` brings it back,
and both are recorded in the audit trail as `soft_delete` / `restore`. Real
`destroy` still hard-erases the row (also audited) — reach for it only for a
genuine "forget me".

## Settings

Configurable values — a currency, a fee, a threshold — go through
`Loam::Configs`, never a hand-rolled constant or a column. `Loam::Configs.get(key)`
resolves, most specific first: the current tenant's override → the global row →
the default declared in `Loam.config_defaults` → `nil`. `set(key, value)` writes
the current tenant's override, `set(key, value, scope: :global)` the app-wide
row, and `reset(key)` drops the override so the key falls back. Values keep their
JSON type (bool, number, string, hash) and an override never leaks to another
tenant. Declare app-wide defaults in `config/initializers/loam.rb`; managers edit
per-tenant values at `/admin/configs`.

## Feature flags

A feature flag answers "is this capability turned ON for this tenant right now",
independent of who is signed in — for a gradual rollout or a kill-switch. This is
NOT permissions: a policy gates a PERSON, a flag gates a CAPABILITY, and the two
coexist. Declare flags in `Loam.feature_defaults` (name → default state +
description); `Loam::Features.on?(:name)` resolves override → global → declared
default → false. `enable`/`disable` set the current tenant's override (add
`scope: :global` for app-wide), `reset` drops it. Guard a controller action with
`require_feature!(:name)` (raises → 404 when off) and hide view UI with
`feature_on?(:name)`; managers flip per-tenant flags at `/admin/features`.
Storage is shared with Settings under the reserved `features.` key prefix, but
flags have their own screen.

## Encrypting a field

Sensitive columns (SSN, tax id, email) are encrypted at rest, per tenant, so a
DB dump leaks nothing and one tenant's key never decrypts another's. Generate
them — `bin/rails g loam:entity Patient name:string ssn:string email:string
--encrypt ssn --encrypt-searchable email` — or declare on the model:

```ruby
include Loam::Encryptable
encrypts :ssn                      # encrypted, not searchable
encrypts :email, searchable: true  # + a blind index for exact-match lookup
```

Read/write is transparent (`patient.ssn` decrypts on read); a searchable field
is found by `Patient.find_by_email(value)`, which matches the per-tenant blind
index — never a LIKE. Rules: a field is NEVER both `encrypts` and `searchable_by`
(ciphertext cannot be LIKE-searched — it raises at load); reading or writing an
encrypted field with no tenant in context raises `MissingTenantError`; the audit
trail records an encrypted change as `[encrypted]`, never the value. Set
`LOAM_MASTER_KEY` (see the initializer) — encryption raises without it. GDPR
export / key rotation: `bin/rails loam:encryption:decrypt_dump[Model,tenant_id]`
/ `loam:encryption:rotate[Model,tenant_id]`.

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
- **Delete with `soft_delete`, not `destroy`.** A business record should be
  hidden and recoverable, not erased. `destroy` hard-deletes; keep it for a
  deliberate, permanent "forget me", never as the default delete path.
- **Never LIKE-search, log, or hand-roll crypto for an encrypted field**, and
  never commit `LOAM_MASTER_KEY`. Use `find_by_<field>` for lookup, let
  `Loam::Encryptable` do the AES-256-GCM, and keep the master key in ENV/credentials.
- **Attachment URLs are capabilities, not addresses.** ActiveStorage blobs live in
  global tables Loam does not tenant-scope: a signed blob URL is fetchable by
  whoever holds it, with no tenant check. Gate files at the record that owns
  them, through its policy, and never paste those URLs anywhere public.

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
