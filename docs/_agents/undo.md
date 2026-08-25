---
title: Undo / Redo
description: "The audit trail as an undo stack (L-704): revert a change with one click, and undo an undo to redo."
nav_order: 7
---

# Undo / redo on the audit trail (L-704)

Every change already writes a `Loam::AuditRecord` with its changeset. `Loam::Undo`
turns that trail into an undo stack: undoing a change applies its inverse and
records **itself** as an audit — so undoing an `undo` entry is redo. There is no
separate command log and no separate redo action.

## Using it

Admin: each record's **History** screen (`/admin/history?type=Equipment&record_id=5`,
linked from the record's show page) lists its audit trail with an **Undo** button
per entry. Undoing needs `update?` on the record (the same gate as editing it).

Code:

```ruby
audit = Loam::AuditRecord.where(auditable_type: "Equipment", auditable_id: id).order(:id).last
Loam::Undo.undo(audit, policy: Loam::Policy.for(record))  # returns the record
Loam::Undo.undoable?(audit)                                # for the button
```

## What each action's inverse is

| Audited action | Undo does |
|---|---|
| `update` / `undo` | revert each field to its *before* value |
| `create` | soft-delete the record |
| `soft_delete` | restore |
| `restore` | soft-delete |

Redo is not special: undoing the `undo`/`soft_delete`/`restore` entry that undo
just wrote re-applies the change.

## The guardrails (each a deliberate skip)

- **Stack order.** A field revert is refused unless the audit is the record's
  **latest** `update`/`undo` — undoing an old change out from under newer ones
  would silently clobber them. Undo walks back one step at a time
  (`NotUndoableError: "a newer change exists — undo that first"`).
- **Encrypted fields** are never reverted: the audit stores `"[encrypted]"`, not
  the old value, so there is nothing to restore to. An update that touched *only*
  encrypted fields has nothing to undo.
- **The workflow column** is never written directly (that is exactly what the
  `Loam::Workflow` transition gate forbids). Undo a state change by performing the
  **reverse transition**, not here.
- **Field-level policy:** pass `policy:` and a field the role may not write is
  skipped.
- **Tenant-scoped throughout:** the audit must belong to the current tenant, and
  the record is looked up through its own default scope (with soft-deleted rows
  visible so a delete can be undone) — never `AuditRecord#auditable`, which is
  unscoped.

## Follow-ups (not built)

Field-level partial-undo UI (choose which fields), out-of-order undo (an explicit
relaxation of the stack rule), and undo of a hard `destroy` (irrecoverable —
only soft-delete is reversible).
