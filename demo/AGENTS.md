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
| MFA & step-up | `Loam::MfaCredential` + `Loam::Totp` (per-user TOTP + recovery codes) | second factor at login, automatic once a user enrolls at `/admin/mfa`; gate a sensitive action with `require_sudo!` (re-auth within 5 min); require MFA per role via `security.mfa_required_roles` |
| AI approval gate | `Loam::PendingActions` + `Loam::PendingAction` (stage → manager approves → executes) | under confirm-mode, `Loam::PendingActions.stage(summary:, on:, action:, changes:)` records a write for review instead of committing; a manager approves at `/admin/pending_actions`; nothing mutates until then |
| Saved views | `Loam::Perspectives` + `Loam::Perspective` (private / role / tenant) | a named index view (filters/sort/columns) saved from the entity index; `Loam::Perspectives.visible_to(entity, user:)` / `default_for` / `resolve`; managed at `/admin/perspectives?entity_type=Name`; `perspective.apply(scope)` filters/sorts only whitelisted columns |
| Concurrent-edit safety | `lock_version` (optimistic) + `Loam::RecordLocks` (advisory) | every generated entity has `lock_version`; a stale update re-renders a conflict diff, never a clobber; `RecordLocks.acquire/holder/release/force_release` warns "who's editing" with a TTL and manager take-over |
| Real-time updates | `Loam::EventStream` (SSE push, default off) | declare patterns in `Loam.broadcast_events` (e.g. `"loam.notification."`); matching events, filtered to the connection's tenant + audience, stream to the browser at `/admin/events/stream`; the bell updates live |
| Response enrichers | `Loam::Enrichers` (computed cross-module blocks) | `register(entity_type, key:, batch:)` in the initializer to attach a computed value onto another entity's response; shown on the admin show screen and under `enrichments` in the API; use `batch:` to avoid N+1 |
| Business rules | `Loam::BusinessRules` + `Loam::BusinessRule` (admin-editable WHEN/THEN) | declare at `/admin/business_rules`: a `trigger` event pattern + a safe `{field, op, value}` condition + typed actions (notify / emit_event / set_field / block_transition); fires tenant-scoped in priority order on matching events; the run log shows why it acted |
| Migration-free field | `custom_fields` jsonb column, read/written via `Loam::CustomFields` | a `Loam::FieldDefinition` row, created via the admin "Field definitions" screen (`/admin/field_definitions`) — never a migration |
| States & approvals | a `workflow` block in the model (`Loam::Workflow`) | `include Loam::Workflow`; add a string column for the state |
| Notifications | `Loam::Notification` rows, read at `/admin/notifications` | `Loam::Notifications.notify(user, title:)` / `notify_role(:manager, title:)`, normally from an event subscriber |
| Search | `searchable_by :col, :col` in the model (`Loam::Searchable`) | declared with the entity for its string/text columns; `Model.search(q)` and the admin's global box at `/admin/search`. HOW it matches is a swappable driver (`Loam::Search.driver`): substring LIKE (default) or the portable word-level TokenDriver — call sites never change |
| SSO (OIDC) | `Loam::Sso` + `Loam::SsoProvider` (per-tenant, admin-configured) | configure at `/admin/sso_providers` (issuer, client_id, client_secret, email domain, JIT role); a matching-domain email is routed to the IdP, verified, and JIT-provisioned/linked; the client_secret is encrypted (needs `LOAM_MASTER_KEY`); SAML/SCIM are seams |
| Dictionaries | `Loam::Dictionary` + `Loam::Dictionaries` (managed lookup lists) | curate at `/admin/dictionaries`; a `FieldDefinition` of type "dictionary" makes a custom field a select of its entries; read via `Loam::Dictionaries.entries`/`default`/`label_for` |
| Task progress | `Loam::Progress` + `Loam::ProgressJob` (live over SSE) | `start(name:, total:)` then `advance`/`complete!`/`fail!`/`cancel!`; percent/ETA push to the `/admin/progress_jobs` bar live; broadcast throttled per-percent; `cancelled?` for a cooperative stop |
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

## Second factor & step-up (sudo)

Admin login gains a TOTP second factor the moment a user enrolls at `/admin/mfa`
(the secret is encrypted per-user; recovery codes are single-use). You do NOT
wire the login step — it is automatic once a credential is active. For a
genuinely sensitive action (revoking access, a bulk change), call `require_sudo!`
in the controller: it re-challenges when the user's last authentication is older
than 5 minutes, then returns them to the action. Step-up gates by RECENCY of
auth and is orthogonal to role — even a manager re-confirms. To force MFA for a
role, set `security.mfa_required_roles` (a `Loam::Configs` array, global or
per-tenant); an un-enrolled user with that role is sent to enrollment at login.
Never store a TOTP secret or recovery code in the clear — `Loam::MfaCredential`
already encrypts / hashes them. Recovery codes are for LOGIN only — step-up
(`require_sudo!`) takes a TOTP code, never a single-use recovery code.

## Staging a write for approval (confirm-mode)

If you are an AI agent running under confirm-mode (`Loam.require_confirmation?`
is true — the MCP tool that runs you sets it), a WRITE must be STAGED for a
human, not committed. Instead of `record.update!(...)`, call:

```ruby
Loam::PendingActions.stage(
  summary: "Raise the excavator's daily rate to 1100",
  on: equipment, action: :update, changes: { daily_rate: 1100 }
)
```

This records a `Loam::PendingAction` with a before/after preview and touches
NOTHING on the target. A manager reviews the queue at `/admin/pending_actions`
and approves — a role-gated workflow transition — and ONLY then does the change
execute, audited to the approver. Identical proposals collapse (idempotency
key); encrypted fields show `[encrypted]` in the preview, never their value.
Loam does not auto-gate Active Record, so a direct `update!` still writes
immediately when you are NOT under confirm-mode — staging is a call you make.
One caveat: a staged update applies raw attribute writes, so do not stage a
workflow-status column directly (that bypasses the transition's role gate) —
stage the transition as a custom `action:` instead. Segregation of duties: the
proposer may not approve their own change unless the tenant sets
`approvals.allow_self_approve` — normally the proposer is the agent and the
approver a human.

## Saved views (perspectives)

A user saves a named view of an entity's admin index — its filters, sort, and
columns — from the index itself ("Save current view"), and manages them at
`/admin/perspectives?entity_type=Name`. Three visibility tiers: `private` (owner
only), `role` (a membership role), `tenant` (everyone). `Loam::Perspectives.visible_to(entity, user:)`
lists what a user may see, `default_for` resolves the applicable default
(private > role > tenant), and the entity index applies the picked/default one.
`perspective.apply(scope)` is SAFE: a filter or sort is honored only if it names
a real, non-plumbing column — a crafted key (arbitrary SQL, or `tenant_id`) is
skipped, never run. Only the owner (or a manager, for shared views) may edit or
delete one, and rows are optimistic-locked against concurrent edits.

## Concurrent-edit safety

`lock_version` (on every generated entity) is the GUARANTEE: a stale update
raises `ActiveRecord::StaleObjectError`, which the generated controller turns into
a "changed since you opened it" conflict — a diff and a retry, never a 500 or a
clobber. Keep the hidden `lock_version` field in the edit form and permit it.
`Loam::RecordLocks.acquire(record, by:)` is the COURTESY: an advisory, TTL'd
"someone is editing this" banner (heartbeat on re-acquire, auto-frees on
soft-delete, manager `force_release`). It warns; it does not block.

## Real-time updates (SSE)

Push events to the browser instead of polling. OPT-IN and default-off: only an
event whose name matches a `Loam.broadcast_events` pattern (set in the
initializer) is eligible, and each is filtered to the connected tenant AND
audience (a payload `user_id` is the sole recipient) before it leaves the server.
The bell already streams `loam.notification.created`; add a pattern to stream
your own events to a live widget. Fan-out is single-process in the prototype
(Redis/SolidCable is the seam — see docs/architecture.md).

## Response enrichers

`Loam::Enrichers.register(entity_type, key:, batch:)` (in the initializer)
attaches a computed block onto ANOTHER module's entity — shown on its admin show
screen and under an `enrichments` key in the API, never mixed into the record's
own attributes. A `batch:` resolver (array → `{ id => value }`) keeps an index one
query, not N. A resolver runs in the current tenant scope and a raising one is
isolated (its key omitted). Caution: don't surface ANOTHER record's encrypted
plaintext through an enricher.

## Business rules

A manager wires automation without a deploy: WHEN an event fires and a condition
holds on the triggering record, THEN run actions — at `/admin/business_rules`.
The condition is DATA, never code: a `{field, op, value}` tree (`and`/`or`/`not`)
over a WHITELIST of real columns + custom fields — no `eval`/`send`, `tenant_id`
and encrypted columns refused, values literal. Actions are a fixed set: `notify`,
`emit_event`, `set_field` (a whitelisted field — NEVER the workflow status column,
which would skip the transition gate), `block_transition`. Rules run tenant-scoped
in priority order, each isolated (a raising rule is logged, not fatal); the run log
shows why each fired. Add a verb by extending `BusinessRules::Actions`/`Condition`,
never by evaluating a rule string.

## Search backends

`searchable_by :col, :col` declares the columns; `Model.search(q)` returns a
tenant-scoped relation. HOW a query matches is a swappable driver
(`Loam::Search.driver`): the default `LikeDriver` is a substring LIKE; the
`TokenDriver` keeps a portable word-level index (`loam_search_tokens`) for
order-independent, whole-word matching; an external engine is a third — all
behind one seam, so NO `searchable_by`/`Model.search` call site changes. Switch it
in the initializer, then `bin/rails loam:search:reindex` once to backfill
(new/updated records self-index). Never `searchable_by` an encrypted field — and
the TokenDriver never tokenizes one either (no plaintext leak into the index).

## Single sign-on (SSO)

A tenant connects its own OIDC provider at `/admin/sso_providers` (issuer,
client_id, client_secret, email `domain`, JIT role). Home-realm discovery routes
a user to their IdP by email domain; on callback a VERIFIED identity is
provisioned just-in-time (or linked to an existing User by verified email — an
UNVERIFIED email is refused, never linked, so there is no account takeover) with
a tenant membership at the mapped role. The client_secret is encrypted at rest,
so `LOAM_MASTER_KEY` must be set. OIDC is shipped end-to-end; SAML and SCIM are
seams behind the protocol interface. In tests, inject `Loam::Sso::FakeProvider`
via `Loam::Sso.builder` so nothing touches the network.

## Dictionaries

Per-tenant managed lookup lists (`Loam::Dictionary`), curated at
`/admin/dictionaries` with no deploy. Use one as a custom-field type: a
`FieldDefinition` of `field_type: "dictionary"` (dictionary key in its `config`)
renders a select of active entries and stores the chosen value — read it with
`custom_field`, its label with `custom_field_label` / `Loam::Dictionaries.label_for`.

## Task progress

A long-running job reports progress live (SSE, no polling): `progress =
Loam::Progress.start(name:, total:)`, then `progress.advance(by:, message:)` per
unit and `complete!`/`fail!`/`cancel!` at the end; check `progress.cancelled?` to
stop early. Pushes id/percent/status to the `/admin/progress_jobs` bar, throttled
per-percent. In a background job wrap the work in `Loam.as_tenant(tenant, actor:)`
(tenant-scoped, not audited; `stale?` flags a dead job).

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
