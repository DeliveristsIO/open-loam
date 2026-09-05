# OpenLoam — Backward-compatibility contract (L-707)

This is the inventory of OpenLoam's **frozen public surfaces**: the things an app or
an agent builds against, that OpenLoam promises not to break without a major-version
bump and a migration path. Everything *not* listed here is an internal detail and
may change in a minor release.

OpenLoam follows semver once it hits 1.0. Until then, breaking changes are still
avoided on these surfaces and always called out in the changelog.

**What "frozen" means:** the *shape* is stable — names, signatures, formats, and
documented semantics. Adding an optional parameter, a new value to an open set,
or a new module is backward-compatible. Removing or renaming a listed thing,
changing a format, or tightening semantics is a breaking change.

---

## 1. Tenancy — the spine

| Contract | Guarantee |
|---|---|
| `OpenLoam::TenantRecord` | Base class for tenant-scoped models; a `default_scope` on `OpenLoam::Current.tenant` filters every query. |
| `OpenLoam.tenant!` / `OpenLoam::MissingTenantError` | A tenant-scoped query with no tenant context **raises**, never widens. |
| `OpenLoam.as_tenant(tenant, actor:) { }` | The one blessed way to establish/switch context; restores the previous on exit. |
| `tenant_id` column on every scoped table | Row-level isolation. Not schema-per-tenant. |

Blessed cross-tenant lookups (the only code allowed to bypass the scope, all in
the gem): `Membership.tenants_for`, `ApiToken.authenticate`, `Sso.provider_for`,
`InboundWebhookSource.resolve`, the scheduler's due-job claim. A host app doing
`.unscoped` in `app/` fails the guardrail lint.

## 2. Domain events

| Contract | Guarantee |
|---|---|
| Event name format | `domain.thing.happened` (`/\A[a-z0-9_]+(\.[a-z0-9_]+){2,}\z/`). |
| `OpenLoam::Events.publish(name, payload)` | Stamps `tenant_id` + `actor_id`; payload is JSON scalars by convention. |
| `OpenLoam::Events.subscribe(name_or_prefix)` | A trailing dot is a domain prefix, else an exact name — **the same rule everywhere** (webhooks, business rules, durable subscribers). |
| Lifecycle events | `OpenLoam::Eventful` publishes `<domain>.<entity>.created/updated/destroyed` on commit. |
| `OpenLoam::DurableEvents.register(key:, to:, call:)` | Persistent subscriber; **at-least-once, unordered**; handler resolved from the boot registry. |

## 3. Generators — the one interface

| Contract | Guarantee |
|---|---|
| `rails g open_loam:install` | Scaffolds the tenancy/auth/admin foundation + `AGENTS.md`. |
| `rails g open_loam:entity Name field:type …` | Scaffolds a tenant-scoped, audited, evented entity with model/migration/admin/API/policy. |
| Generated file locations | `app/models`, `app/controllers/admin`, `app/controllers/api`, `config/routes.rb` conventions. |
| `AGENTS.md` byte budget | ≤ 32 KB (enforced by a guardrail test) so an agent harness never truncates its tail. |

## 4. Authorization

| Contract | Guarantee |
|---|---|
| `OpenLoam::Policy` `field :name, writable:, readable:` | Field-level access declared per entity policy class. |
| `writable?/readable?/custom_field_writable?/custom_field_readable?` | The check API controllers and generators call. |
| Roles | `OpenLoam::Membership#role` (a string); the coarse authorization axis. |
| `OpenLoam::Permissions` wildcard strings | `*` = all, trailing `.*` = prefix, else exact; `OpenLoam.can?` / `require_permission!`; deny-by-default. |
| `OpenLoam::NotAuthorizedError` → 403 | The mapping admin controllers rely on. |

## 5. Encryption at rest

| Contract | Guarantee |
|---|---|
| Ciphertext format | `v1:base64(iv‖tag‖ciphertext)` (no AAD) and `v2:` (AAD-bound to tenant+table+column). **Both stay readable**; `open_loam:encryption:rotate` upgrades v1→v2. |
| Algorithm | AES-256-GCM, random 12-byte IV, per-tenant key via HKDF-SHA256 behind a `KeyProvider` seam. |
| Blind index | Searchable encrypted field carries an HMAC-SHA256 `<field>_hash` for exact match. The key derives per **(tenant, table, column)**, like the v2 AAD — as of 0.3.0, which changed the derivation and so the stored values; the column's shape and name did not change. Re-index with `open_loam:encryption:rotate`. |
| Audit redaction | An encrypted field's change is recorded as `"[encrypted]"`, never the value; the hash column is dropped. |

## 6. Webhooks (in & out)

| Contract | Guarantee |
|---|---|
| Outbound signature | `X-OpenLoam-Signature: sha256=<hex>` where hex = `HMAC-SHA256(endpoint.secret, exact_body)`. **Pinned by a fixed test vector** — changing it breaks every receiver. |
| Outbound body | `{ "event": …, "payload": …, "tenant_id": … }`. |
| Inbound receiver | `POST /webhooks/:token`; HMAC over the raw body in the source's `signature_header`; `(source, external_id)` replay ledger; uniform `401` on any auth failure. As of 0.3.0 `external_id` is **SHA-256 of the raw body** — the only signed material. The `delivery_id_header` setting is gone: deriving the ledger key from an unsigned header let one captured delivery be replayed indefinitely. |

## 7. JSON API

| Contract | Guarantee |
|---|---|
| Auth | `Authorization: Bearer <token>` (`OpenLoam::ApiToken`). |
| Routes | `/api/<entities>` CRUD per entity. |
| Entity JSON | Columns + custom fields; encrypted fields decrypted, `<field>_hash` dropped; enrichments under `enrichments`. |
| OpenAPI | Self-documented as **OpenAPI 3.1** at `/admin/api_docs(.json)`; request schemas expose writable fields only (never `tenant_id`). |

## 8. Custom fields

| Contract | Guarantee |
|---|---|
| Storage | A `custom_fields` json column + `OpenLoam::FieldDefinition` rows (typed; `writable_roles`/`readable_roles`). |
| Access | `record.custom_field(:name)` / `set_custom_field`; unknown field raises `UnknownCustomFieldError`. |
| Index query API | `OpenLoam::CustomFieldIndex.filter(model, key, op, value)` / `order(model, key, dir)`; ops `#{OpenLoam::CustomFieldIndex::OPS}`; correctness-first fallback + self-heal; read-ACL enforced. |

## 9. Audit & undo

| Contract | Guarantee |
|---|---|
| `OpenLoam::AuditRecord` | `auditable_type/id`, `action`, `changeset` (Rails `saved_changes` shape `{field=>[before,after]}`, `"[encrypted]"` for encrypted), `actor_id`, tenant, `created_at`. Append-only. |
| Audit actions | `create` / `update` / `destroy` / `soft_delete` / `restore` / `undo` (an open set — new labels may be added). |
| `OpenLoam::Undo.undo(audit, policy:)` / `undoable?` | Applies the inverse and records itself; latest-change-only; skips encrypted + workflow columns. |

## 10. Other keyed surfaces

| Contract | Guarantee |
|---|---|
| Settings | `OpenLoam::Configs` resolve order override → global → default; `OpenLoam::Features` under the reserved `features.` prefix. |
| Scheduler | `OpenLoam::Scheduler.register(key:, job_class:, schedule:, scope:)`; cron 5-field + `interval:N`; `job_class` allowlisted to a real ActiveJob. |
| Search | `OpenLoam::Search.driver=` seam; `searchable_by` / `Model.search(q)` unchanged across drivers. |
| SSE frame | Per-tenant `text/event-stream`; frames carry ids/scalars only, audience-filtered. |
| Overrides | `OpenLoam::Overrides.disable/replace(registry, key)`; `check!` warns on stale keys. |
| Translations | `translates :field` overlays the current-locale value over the base column (the base is never lost). |

---

## Changing a frozen contract

1. Prefer **additive**: a new optional arg, a new value in an open set, a new module.
2. If a break is unavoidable: ship the new surface alongside the old, mark the old
   deprecated in the changelog, keep it working for one minor cycle, then remove it
   in a major bump. (The `v1:`→`v2:` encryption format is the model — old data
   keeps reading while new writes use the new format.)
3. Always add a regression test that pins the contract (see the webhook signature
   vector) before changing anything near it.
