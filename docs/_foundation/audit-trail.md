---
title: Audit trail
description: Change tracking that's on by default, not a log call someone has to remember to add.
nav_order: 4
permalink: /foundation/audit-trail/
---

# Audit trail

## Concept

`Loam::Auditable` (`lib/loam/auditable.rb`) is included in every generated
entity. It hooks `after_create`, `after_update` (only when there are real
changes), and `after_destroy`, and writes a `Loam::AuditRecord` tagged with
the tenant, the acting actor, the action (`"create"`/`"update"`/`"destroy"`),
and the changeset. "Who changed the excavator's price, and when" is answered
structurally — nothing to remember to log.

```ruby
class Equipment < Loam::TenantRecord
  include Loam::Auditable
end

Loam.as_tenant(acme, actor: manager) do
  equipment = Equipment.create!(name: "Excavator", daily_rate: 900)
  equipment.update!(daily_rate: 950)
end

Loam::AuditRecord.where(auditable_type: "Equipment", auditable_id: equipment.id).pluck(:action)
# => ["create", "update"]
```

## What's recorded

`created_at`/`updated_at` are excluded from the changeset (`IGNORED_ATTRIBUTES`
in `lib/loam/auditable.rb`) — timestamp churn isn't a meaningful change. A
`destroy` records an empty changeset (the row is gone; the fact of deletion is
what matters). `Loam::SoftDeletable` reuses the same audit path to record
`soft_delete`/`restore` as their own distinct actions rather than a generic
`update`.

## Encrypted fields are redacted, not skipped

An encrypted column's change is still recorded — as the fact that it changed,
never the value. Neither the plaintext nor the ciphertext is written to the
audit row: a ciphertext still leaks length and, over time, correlations, so
`loam_redact_encrypted` replaces the value with the literal string
`"[encrypted]"`, and drops the blind-index sibling column entirely. This is a
no-op for models without `Loam::Encryptable` — the check is
`respond_to?(:loam_encrypted_attributes)`.

## Why Loam behaves this way

Audit-by-default means a reviewer never has to ask "does this model log
changes" — every `Loam::TenantRecord` that includes `Auditable` (which the
entity generator wires in automatically) does, unconditionally, from the
moment it's created. The alternative — audit logging as an opt-in concern a
developer adds per model when they remember to — is exactly the kind of
per-ticket, inconsistent security property the
[golden-tasks control run]({% link _agents/golden-tasks.md %}) found missing
across hand-rolled vanilla-Rails apps.

## Agent guidance

- Don't hand-write a changelog or a second `xxx_history` table — extend
  `Loam::AuditRecord` usage (query it, don't duplicate it).
- The audit trail is also the undo mechanism's data source — see
  [Undo / redo]({% link _agents/undo.md %}).
- Never log or expose the *value* of an encrypted field anywhere, including a
  custom audit view — `Loam::Auditable` already redacts it for you; a
  hand-rolled log statement elsewhere would defeat that.

## Related pages

- [Tenant isolation]({% link _foundation/tenant-isolation.md %})
- [Undo / redo]({% link _agents/undo.md %})
- [Encryption at rest]({% link _agents/encryption.md %})
