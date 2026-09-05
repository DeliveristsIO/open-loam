---
title: How OpenLoam works
description: The shape of the system — tenancy, authorization, audit, events, admin — and where to go deeper.
nav_order: 1
permalink: /foundation/overview/
---

# How OpenLoam works

OpenLoam is an **opinionated foundation, delivered as one Rails engine gem.** Each
pillar — tenancy, authorization, audit, events, admin — is a small,
self-contained implementation living under `OpenLoam::`. The value is the
*fusion*: they all agree with each other and with the tenancy boundary on day
zero, plus an [agent-legibility layer]({% link _agents/index.md %}) on top so
a coding agent doesn't have to rediscover any of it per task.

> **Prototype note (2026-08).** The original plan was to *wrap* proven gems
> (`acts_as_tenant`, `pundit`, `paper_trail`, Rails Event Store, Avo). The
> prototype instead ships **minimal in-gem implementations** behind OpenLoam's own
> conventions — the smallest surface that proves the conventions and the agent
> flow end to end (see [ADR 0002]({% link _adr/0002-in-gem-implementations.md %})).
> Read one at a time against the code, those swaps are now settled: tenancy,
> audit and authorization stay in-gem, and the one real gap — event capture —
> was closed in-gem too
> ([ADR 0007]({% link _adr/0007-proven-gem-swaps-resolved.md %})). The
> `OpenLoam::` API remains the contract either way.

## Shape

OpenLoam ships as a single Rails **engine** + generators + an `AGENTS.md`
contract, layered over a standard Rails 8 app.

```
app/                     your business (the 20%)
lib/open_loam/                the foundation (the 80%)
  tenant_record.rb       tenant model base class + default-scope isolation
  current.rb             per-request tenant/actor context
  policy.rb              roles + field-level write rules
  auditable.rb           change tracking, on by default
  events.rb / eventful.rb  domain event bus + lifecycle events
  custom_fields.rb       runtime fields (OpenLoam::FieldDefinition + json column)
  workflow.rb            states, transitions, role-gated approvals
  lifecycle.rb           on_tenant_created hooks + open_loam:sync
app/models/open_loam/         engine models (Tenant, Membership, AuditRecord, …)
lib/generators/open_loam/     install + entity generators (the one interface)
AGENTS.md                agent conventions + guardrails (byte-budgeted)
```

## The system, visually

A polished, shareable version of these diagrams (plus the full module
catalogue) lives as an [**architecture map**](https://claude.ai/code/artifact/949311d3-5e14-4f07-a8ad-7b1bb5bd87ad).
The two graphs below are Mermaid — they also render inline on GitHub.

**The module map** — two things sit at the center: `OpenLoam::TenantRecord` (the
ground every model stands on) and the event bus (how modules talk without
knowing about each other). An arrow reads as "feeds" or "builds on".

{% raw %}
```mermaid
flowchart TB
  TR{{"OpenLoam::TenantRecord · isolation"}}:::core
  BUS(["OpenLoam::Events · event bus"]):::bus
  subgraph IA["Identity and access"]
    MEM["Membership · roles"]:::n
    POL["Policy · field-level"]:::n
    MFA["MFA · SSO · throttle"]:::n
  end
  subgraph DF["Data and modeling"]
    CF["Custom fields"]:::n
    IDX["Field index · read ACL"]:::n
    ENC["Encryption"]:::n
    WF["Workflow"]:::n
  end
  subgraph EA["Automation · event-driven"]
    BR["Business rules"]:::n
    NOTE["Notifications"]:::n
    DUR["Durable subscribers"]:::f
    SSE["SSE stream"]:::n
  end
  subgraph INT["Integration"]
    WHO["Webhooks · out"]:::f
    WHI["Webhooks · in"]:::f
    API["JSON API · OpenAPI"]:::n
  end
  TR --- IA
  TR --- DF
  TR --- EA
  TR --- INT
  MEM --> POL
  POL -. guards .-> API
  POL -. guards .-> CF
  ENC -. protects .-> CF
  CF --> IDX
  WF --> BUS
  CF --> BUS
  WHI --> BUS
  BUS --> BR
  BUS --> NOTE
  BUS --> DUR
  BUS --> SSE
  BUS --> WHO
  classDef core fill:#F0E2D2,stroke:#9A5522,color:#2A241C;
  classDef bus fill:#DCEAE7,stroke:#2F6F6A,color:#1D3F3B;
  classDef n fill:#FFFFFF,stroke:#C3B49C,color:#2A241C;
  classDef f fill:#EAF3F1,stroke:#2F6F6A,color:#1D3F3B;
```
{% endraw %}

**The event backbone** — publishing is cheap and knows nothing about who
listens. Subscribers come in two contracts: *ephemeral* (in-process,
best-effort) and *durable* (persisted, retried, at-least-once). External
systems join the same bus from both directions.

{% raw %}
```mermaid
flowchart LR
  EXT[["external system"]]:::ext -->|"POST /webhooks/:token · HMAC · replay-safe"| IN["Inbound webhook"]:::f
  IN --> PUB(["publish"]):::bus
  MODEL["model save / service"]:::n --> PUB
  PUB --> EPH{{ephemeral}}:::eph
  PUB --> DURP{{durable}}:::durp
  EPH --> WD["webhook dispatch"]:::n
  EPH --> RULES["business rules"]:::n
  EPH --> STREAM["SSE to browser"]:::n
  DURP --> ROW["EventDelivery row"]:::f
  ROW --> JOB["job runs handler"]:::n
  JOB -->|ok| DONE([delivered]):::ok
  JOB -->|fail| RETRY["retry + backoff"]:::n
  RETRY -->|exhausted| DEAD([dead-letter]):::warn
  SWEEP["redelivery sweep"]:::f -. re-enqueues lost jobs .-> ROW
  WD -->|signed JSON| OUT[["external endpoint"]]:::ext
  classDef ext fill:#ECE7DD,stroke:#B7AE9E,color:#4A4436;
  classDef bus fill:#DCEAE7,stroke:#2F6F6A,color:#1D3F3B;
  classDef n fill:#FFFFFF,stroke:#C3B49C,color:#2A241C;
  classDef f fill:#EAF3F1,stroke:#2F6F6A,color:#1D3F3B;
  classDef eph fill:#F5EFE6,stroke:#9A5522,color:#2A241C;
  classDef durp fill:#F0E2D2,stroke:#9A5522,color:#2A241C;
  classDef ok fill:#DDEBD9,stroke:#4B7A43,color:#274023;
  classDef warn fill:#F3E0CE,stroke:#B26A2E,color:#5A3413;
```
{% endraw %}

## The pillars, briefly

- **Tenant isolation.** Every business model inherits `OpenLoam::TenantRecord`; a
  missing tenant context raises instead of widening a query. Structural, not a
  convention. → [Tenant isolation]({% link _foundation/tenant-isolation.md %})
- **Authorization.** A `OpenLoam::Policy` per entity: role-based action checks
  plus field-level `writable:`/`readable:` rules. Orthogonal to tenancy — a
  member of the right tenant can still be denied a specific action or field.
  → [Authorization]({% link _foundation/authorization.md %})
- **Audit.** Every create/update/destroy on an audited model writes a
  `OpenLoam::AuditRecord` with actor, action, and changeset — automatically.
  → [Audit trail]({% link _foundation/audit-trail.md %})
- **Domain events.** `OpenLoam::Events` over `ActiveSupport::Notifications`;
  *ephemeral* (in-process, best-effort) and *durable* (persisted, retried,
  dead-lettered) subscriber tiers. → [Events]({% link _agents/events.md %})
- **Admin.** A generated, Hotwire-free ERB console — CRUD, comments,
  attachments, global search, permission-aware — comes with every entity for
  free.

Every other pillar (workflow, custom fields, encryption, MFA, SSO, scheduler,
search, business rules, and the rest) is documented in the
[pillar implementation reference]({% link _reference/pillars.md %}), with
what the prototype ships versus the roadmap target for each.

## Agent-legibility layer

What makes OpenLoam *agent-native* rather than just a starter kit:

1. **`AGENTS.md`** — the canonical map, byte-budgeted (≤32 KB, enforced by a
   [guardrail]({% link _agents/guardrails.md %})) so an agent harness never
   silently truncates its tail. → [The agent contract]({% link _agents/agent-contract.md %})
2. **Generators as the interface** — agents add features by invoking OpenLoam
   generators, not free-form file creation. Output is predictable and
   reviewable. → [Generators]({% link _reference/generators.md %})
3. **Structural guardrails** — tenancy and authorization are enforced by base
   classes and default scopes, so an agent *can't* silently produce a
   cross-tenant leak or an unauthorized action; it shows up as a failing test.
   → [Guardrails]({% link _agents/guardrails.md %})
4. **Measured** — a golden-tasks benchmark runs agents against fresh apps and
   audits the result behaviorally, not just by test count.
   → [Golden tasks]({% link _agents/golden-tasks.md %})

## Example: what "add a feature" looks like

> "Add a `Subscription` entity: fields plan, status, renews_at; tenant-scoped;
> admin screen; only Billing role can edit; emit `billing.subscription.renewed`."

An agent (or human) runs the entity generator, declares the policy rule, adds
the workflow/event, and the admin panel comes with it — each a conventional,
audited, tenant-scoped step. No decisions about *how* tenancy or permissions
work, because OpenLoam already decided. This is exactly the shape the
[golden-tasks benchmark]({% link _agents/golden-tasks.md %}) exercises.

## Non-goals

- Not a commerce product (that's Spree/Solidus) — OpenLoam is domain-agnostic.
- Not a low-code builder — it produces normal, readable Rails code.
- Not a fork of Rails — it's an engine + conventions on top of stock Rails.

## Decisions made in the prototype

The bigger calls are recorded as ADRs: [row-level tenancy]({% link _adr/0001-row-level-tenancy.md %}),
[in-gem implementations before wrapping proven gems]({% link _adr/0002-in-gem-implementations.md %}),
[a generated ERB admin]({% link _adr/0003-generated-erb-admin.md %}),
[the byte-budgeted AGENTS.md contract]({% link _adr/0004-agents-md-contract.md %}),
and [events as the decoupling seam]({% link _adr/index.md %}). A few smaller
calls aren't ADRs yet, in brief:

- **Custom-fields engine** → a json column + `FieldDefinition` typed accessors,
  not full EAV. Portable `json` today; `jsonb`/GIN is the production target; a
  read-model index (`OpenLoam::CustomFieldIndex`) is the scaling path.
- **Encryption at rest** → AES-256-GCM with a random 12-byte IV per value,
  version-tagged so a rotated key or new scheme can coexist with old rows.
  Keys derive per tenant AND per purpose via HKDF-SHA256 from one master key,
  behind a `KeyProvider` seam a Vault/KMS provider can drop into.
- **MFA key scope** → an MFA secret is keyed by the *user*, not the tenant —
  it must verify at login before any tenant is chosen, so a per-tenant key
  would be a lockout bug.
- **Approval gate** → a staging primitive (`OpenLoam::PendingActions.stage`), not
  a global Active Record interceptor — OpenLoam has no single write chokepoint, so
  a confirm-mode caller checks `OpenLoam.require_confirmation?` and stages
  explicitly. See [Confirm-mode]({% link _agents/confirm-mode.md %}).
- **Real-time push is single-process in the prototype.** The default SSE
  broadcaster only sees events instrumented in its own process — correct for
  the single-worker prototype, and a documented seam (`OpenLoam::EventStream.broadcaster`)
  for a Redis/SolidCable backend at multi-process scale.
