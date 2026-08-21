# Loam — concept & positioning

## The one-sentence pitch

An opinionated, AI-native Rails foundation that pre-decides the 80% every
business app shares — tenancy, permissions, custom entities, events, audit,
admin — so humans and AI agents build the 20% that's the actual business.

## Who it's for

- **Product teams** building SaaS back-offices, internal tools, ops consoles,
  vertical CRMs/ERPs — who don't want to spend the first quarter on plumbing.
- **Agencies / solo builders** shipping client business apps fast, repeatably.
- **Teams betting on AI-assisted development** who need a codebase agents can
  extend without breaking tenancy or permissions.

## The 80 / 20

```
┌─────────────────────────────────────────────┐
│  YOUR BUSINESS  (the 20% — what you sell)     │  ← you + your agents
│  entities · workflows · screens · rules       │
├─────────────────────────────────────────────┤
│  LOAM  (the 80% — decided for you)            │  ← already done
│  tenancy · RBAC · custom entities · events    │
│  audit · admin · agent conventions            │
├─────────────────────────────────────────────┤
│  RAILS  (the framework)                        │
└─────────────────────────────────────────────┘
```

Mercato's insight, stated plainly: the value isn't features, it's **decisions
you no longer have to make** — and decisions an agent no longer has to guess.

## Where Loam sits

| | Loam | Open Mercato | Frappe / ERPNext | Bullet Train | Spree/Solidus |
|---|------|--------------|------------------|--------------|---------------|
| Stack | **Rails** | TS / Next | Python | Rails | Rails |
| Category | Foundation | Foundation | Foundation | SaaS starter | Commerce product |
| Multi-tenancy | ✅ core | ✅ | ✅ | ✅ | Enterprise-only |
| RBAC | ✅ core | ✅ | ✅ | ✅ | ✅ |
| Custom entities | ✅ core | ✅ | ✅ (DocTypes) | ~ field types | metafields |
| Event backbone | ✅ core | ✅ | ~ | webhooks | Event Bus |
| Audit | ✅ core | ✅ | ✅ | ✅ | ~ |
| **AI-agent conventions** | ✅ **first-class** | ✅ | ❌ | ❌ | ❌ |
| Domain | business / any | CRM/ERP/commerce | ERP | generic SaaS | commerce |

**The gap Loam fills:** a Rails project that is *both* a real business foundation
*and* built for AI agents to extend. Today those two properties live in different
projects. (Research: no Rails project unifies them; the closest structural analog,
Frappe/ERPNext, is Python.)

## Why Rails, specifically

Convention-over-configuration makes Rails arguably the **most agent-legible**
framework already — a well-built Rails app has one obvious place for everything.
Loam pushes that legibility up a level: from "where does a controller go" to "how
is a tenant-scoped, permissioned, audited business domain built." The framework
does half the work of making agents effective; Loam does the rest.

## Business model (open-core)

Mirrors the foundations Loam stands on (Bullet Train, Rails itself):

- **Loam Core** — MIT, self-host. The conventions, generators, agent pack. Free;
  the adoption funnel.
- **Loam Team / Enterprise** — SSO, advanced RBAC/policy management, tenant
  analytics, compliance/audit exports, priority support.
- **Managed** — hosted single-tenant instances for teams who won't operate it.
- **Marketplace** — domain packs (a CRM pack, a billing pack, an inventory pack)
  and agent packs, built on the conventions.

The moat isn't code — it's the **conventions + the agent legibility + the domain
packs** compounding on top of them.
