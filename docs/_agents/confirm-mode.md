---
title: Confirm-Mode
description: Staging a write as a PendingAction for manager approval instead of committing it directly.
nav_order: 3
---

# Staging a write for approval (confirm-mode)


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

