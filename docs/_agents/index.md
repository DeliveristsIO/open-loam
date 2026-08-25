---
title: Agents
description: Why Loam is built for coding agents, the contract it gives them, and how well that measurably works.
permalink: /agents/
---

# Agents

A coding agent works better on a repository that gives it: one obvious place
for new code, an explicit architecture, generators instead of free-form file
creation, executable constraints instead of prose it can skim past, and fast
feedback when it gets something wrong. Loam is built so a model doesn't have
to rediscover the application's tenancy and authorization model from scratch
on every task — it reads `AGENTS.md` once, and the rest is enforced.

```text
business requirement
        ↓
coding agent
        ↓
AGENTS.md — the agent contract
        ↓
generators + conventions
        ↓
implementation
        ↓
guardrails + tests  ──fail──> agent corrects, loop repeats
        │
       pass
        ↓
      done
```

## Start here

- [**The agent contract**]({% link _agents/agent-contract.md %}) — what
  `AGENTS.md` is, what an agent should read first, and the invariants it
  commits to.
- [**Guardrails**]({% link _agents/guardrails.md %}) — how those invariants
  are enforced as failing tests, not just documentation.
- [**Golden tasks**]({% link _agents/golden-tasks.md %}) — the benchmark
  methodology, and the real (internal, disclosed) numbers on whether any of
  this actually changes agent behavior.

## Subsystem deep-dives

`AGENTS.md` is byte-budgeted (≤32 KB), so anything past a one-line summary in
its table lives here instead. Read the relevant page before touching that
subsystem.

- [MCP server]({% link _agents/mcp.md %}) — exposing Loam to an AI agent
- [Events]({% link _agents/events.md %}) — ephemeral vs durable subscribers
- [Confirm-mode]({% link _agents/confirm-mode.md %}) — staging a write for approval
- [Encryption at rest]({% link _agents/encryption.md %})
- [Single sign-on (SSO)]({% link _agents/sso.md %})
- [Scheduler]({% link _agents/scheduler.md %})
- [Undo / redo]({% link _agents/undo.md %})
- [Inbound webhooks]({% link _agents/inbound-webhooks.md %})
- [Bulk import / export]({% link _agents/bulk-import-export.md %})

## Related pages

- [Foundation]({% link _foundation/overview.md %}) — the tenancy,
  authorization, and audit guarantees the agent contract assumes.
- [Reference]({% link _reference/configuration.md %}) — configuration and
  generator syntax.
