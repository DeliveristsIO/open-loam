# MCP server — exposing Loam to an agent (L-302, tools-only v1)

Loam ships an [MCP](https://modelcontextprotocol.io) server so an AI agent
(Claude Code, Cursor, Codex) can work **inside** a Loam app safely: discover the
domain, read tenant-scoped records, and **propose** writes that a human approves.
It never commits a write itself.

## Run it

```
LOAM_MCP_TOKEN=<a Loam API token>  bin/rails loam:mcp:serve
```

Point your MCP client at that command. Transport is the MCP-spec **stdio**
binding (newline-delimited JSON-RPC); stdout carries JSON-RPC only, all logs go
to stderr. The token authenticates **once** at startup (it is an env var, never a
tool argument, so it can't leak into a transcript): the agent then acts as that
token's user, in that tenant — *whatever that user may do, no more*.

## The four tools (v1)

| Tool | Does |
|---|---|
| `list_entities` | the tenant's business entities (the API-exposed ones) |
| `describe_entity` | columns + types, custom fields, workflow (states/transitions), and which fields the current role may read/write |
| `query_entity` | read records — tenant-scoped, **only readable fields**, whitelisted filters/sort, limit capped at 100 |
| `stage_write` | **propose** an update — staged as a `Loam::PendingAction` for a human manager to approve; it does NOT take effect until approved |

## Why it's safe by construction

Every gate is a Loam gate reused, not a new one:

- **Tenant isolation** — the token establishes tenant + actor; every call runs in
  `Loam.as_tenant`, and `Loam::Current` is reset between calls.
- **No arbitrary classes** — entity names resolve against an allowlist of
  API-exposed `TenantRecord` descendants, never a bare `constantize`.
- **Read ACL** — `query_entity` emits only `policy.readable?` columns and readable
  custom fields (encrypted values decrypted, blind-index columns dropped); a
  **filter on a field the role can't read is refused** (the L-711 inference-oracle
  guard, one layer up), and sort/filter fields are whitelisted (L-401/L-711).
- **Writes can't commit** — `stage_write` only stages a `PendingAction` (the
  confirm-mode approval gate). It accepts only policy-writable columns, refuses
  the workflow column (that goes through a transition), and refuses
  `id`/`tenant_id`/`lock_version`. A manager approves in the admin.

## Scope (v1) and follow-ups

Tools-only, stdio only. No MCP resources/prompts/notifications, no HTTP
transport. `stage_write` is update-only, real columns only. **Shipped ahead of the
dogfood signal at the user's request** — the roadmap gates the server's *depth*
(which tools an agent actually reaches for) on a real dogfood run; this v1 is the
safe read-mostly core to build that signal on. Follow-ups: custom-field + create/
destroy staging, an HTTP transport, and whichever tools the dogfood shows are
missing.
