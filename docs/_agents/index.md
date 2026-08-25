---
title: Agent Deep-Dives
description: Subsystem deep-dives with sharp edges, linked from AGENTS.md so the agent contract stays inside its byte budget.
permalink: /agents/
---

# Agent deep-dives

`AGENTS.md` is byte-budgeted (≤32 KB), so anything past a one-line summary
lives here instead — linked from the table by topic. Read the relevant page
before touching that subsystem.

- [MCP server]({% link _agents/mcp.md %}) — exposing Loam to an AI agent
- [Events]({% link _agents/events.md %}) — ephemeral vs durable subscribers
- [Confirm-mode]({% link _agents/confirm-mode.md %}) — staging a write for approval
- [Encryption at rest]({% link _agents/encryption.md %})
- [Single sign-on (SSO)]({% link _agents/sso.md %})
- [Scheduler]({% link _agents/scheduler.md %})
- [Undo / redo]({% link _agents/undo.md %})
- [Inbound webhooks]({% link _agents/inbound-webhooks.md %})
- [Bulk import / export]({% link _agents/bulk-import-export.md %})
