# OpenLoam — 90-Day Product & Business Plan

## Positioning

**OpenLoam**  
> The Rails foundation for AI-built business software.

Alternative, more sales-oriented:

> Build serious business software. Skip the boilerplate.

OpenLoam should be positioned as:

- a **Rails framework**
- for **business applications**
- with **AI-native development conventions**

It should **not** start as:

- an ERP
- a CRM product
- an ecommerce engine
- a low-code platform

OpenLoam should be the foundation for building:

- CRM systems
- ERP-like systems
- backoffice tools
- partner portals
- operations platforms
- workflow systems
- inventory systems
- booking backends
- B2B applications

---

# Core Thesis

OpenLoam should not be “Open Mercato rewritten in Rails”.

The stronger thesis is:

> **AI-native business application framework for Rails.**

The goal is to provide the architecture, conventions, infrastructure and domain primitives required to build serious business software quickly and safely.

The product should optimize for two things:

1. **faster delivery for developers and agencies**
2. **predictable implementation by AI agents**

The first 90 days should prove that OpenLoam can materially accelerate a real Deliverists project.

---

# 90-Day Plan

## Days 1–14 — OpenLoam Core

Build only the foundation.

### Core entities

- `User`
- `Organization`
- `Membership`

### Platform capabilities

- authentication
- multi-tenancy
- roles
- permissions
- policies
- audit log
- comments
- attachments
- notifications
- events
- custom fields
- API
- webhooks
- basic UI primitives

### Deliverables

The repository should already look like a real product:

- README
- architecture documentation
- contribution guide
- demo application
- installation command
- CI
- tests
- clear conventions

### Do not build yet

- accounting
- invoicing
- warehouse management
- ecommerce
- billing
- marketplace features

---

## Days 15–30 — Developer Experience

Developer experience should become one of OpenLoam's main advantages.

Target something like:

```bash
bin/rails generate open_loam:resource Opportunity \
  name:string \
  value:decimal \
  stage:string
```

The generator should create as much of the complete business feature as possible:

- model
- migration
- policy
- permissions
- UI
- filtering
- audit trail
- API
- tests

### Build reusable primitives for

- tables
- forms
- filters
- pagination
- dashboards
- permissions
- activity feeds
- notifications
- actions

The goal is to make the “correct OpenLoam way” the easiest way to implement a feature.

---

## Days 31–45 — AI Layer

This is where OpenLoam should start differentiating itself from a standard Rails starter kit.

### Add

```text
AGENTS.md
architecture/
recipes/
examples/
conventions/
```

Document:

- where models belong
- how authorization works
- how tenancy works
- how workflows are implemented
- how events are emitted
- how notifications are created
- how APIs are exposed
- how tests should be written
- how modules are structured

### Golden AI Tasks

Create an initial benchmark of tasks such as:

1. Add approval for purchase orders above €10,000.
2. Add a custom field to Company.
3. Create a new permission.
4. Add a dashboard metric.
5. Create a webhook on status change.
6. Add a REST endpoint.
7. Add a scheduled job.
8. Add a notification.
9. Add a workflow state.
10. Modify an existing workflow.

Run these repeatedly with coding agents.

Measure:

- completion rate
- test pass rate
- architecture violations
- number of human interventions
- implementation time

---

## Days 46–60 — Reference CRM Module

Build exactly one business module.

Recommended: **CRM**

The goal is not to compete with HubSpot.

The CRM exists to prove that the OpenLoam primitives work together.

### Entities

```text
Company
Contact
Lead
Opportunity
Pipeline
Task
Activity
```

### The module should demonstrate

- multi-tenancy
- authorization
- custom fields
- audit trail
- filtering
- workflows
- notifications
- events
- API
- reporting
- search

Do not expand into dozens of CRM features.

Keep the module intentionally small.

---

## Days 61–75 — Deliverists Dogfooding

Use OpenLoam in a real application.

Preferably:

- a real client project
- an internal Deliverists system
- a design-partner project

This is the most important phase.

### Measure

For every meaningful feature, compare:

```text
Vanilla Rails estimate
vs
OpenLoam + AI actual
```

Track:

- hours saved
- code generated
- bugs introduced
- architecture violations
- AI interventions
- reusable primitives discovered

### Target

OpenLoam should reduce implementation time by at least:

> **25–30%**

Longer-term target:

> **30–50%**

If it does not save meaningful development time, rethink the architecture before expanding the product.

---

## Days 76–90 — Public Launch

Launch OpenLoam publicly.

### Release

- public GitHub repository
- documentation site
- demo application
- example business application
- short landing page
- installation guide
- AI development guide

### Primary demo

Do not lead with a feature checklist.

Show:

> **From `rails new` to a multi-tenant business application in 10 minutes.**

### Second demo

Show an AI agent receiving a business requirement:

```text
Add purchase orders.

Purchase orders belong to suppliers.

Orders above €10,000 require approval
from a finance manager.

Send a notification after approval.

Expose approved orders through the API.
```

The agent should correctly create:

- migration
- model
- permissions
- policy
- workflow
- event
- notification
- API
- UI
- tests

This should become one of OpenLoam's strongest product demonstrations.

---

# OpenLoam Core — V1 Scope

| Area | V1 |
|---|---|
| Identity | User, authentication |
| Tenancy | Organization, Membership |
| Authorization | roles, permissions, policies |
| Data | custom fields |
| Audit | immutable audit/activity log |
| Collaboration | comments, attachments |
| Async | jobs, notifications |
| Integration | events, webhooks, API |
| Workflow | states, transitions, approvals |
| UI | forms, tables, filters, pagination |
| Search | global search |
| AI | architecture docs, agent conventions |
| DX | Rails generators |
| Deploy | production-ready defaults |

---

# Explicit Non-Goals for V1

Do not build:

- billing
- accounting
- warehouse management
- ecommerce
- marketplace
- payroll
- full ERP
- full CRM
- low-code page builder

Every one of these can become a module later.

---

# Suggested Repository Structure

Avoid splitting OpenLoam into many gems too early.

Start with a monorepo and maintain strong internal boundaries.

```text
open_loam/
├── core/
│   ├── accounts/
│   ├── identity/
│   ├── permissions/
│   ├── audit/
│   ├── events/
│   ├── custom_fields/
│   ├── notifications/
│   └── workflows/
│
├── modules/
│   └── crm/
│
├── ai/
│   ├── AGENTS.md
│   ├── architecture/
│   ├── recipes/
│   └── examples/
│
├── demo/
│
├── docs/
│
└── spec/
```

Only split modules into separate gems or Rails engines once real usage proves that independent installation is necessary.

---

# The Most Important Product Feature

The most important feature is not CRM.

It is not RBAC.

It is not workflow.

It is:

> **AI can safely modify a OpenLoam application because OpenLoam gives the agent strong conventions.**

For a prompt such as:

```text
Add purchase orders.

Purchase orders belong to suppliers.

Every order above €10,000 requires approval
from a finance manager.

Send a notification when the order gets approved.

Expose approved orders through the API.
```

The agent should automatically understand that it needs to consider:

```text
model
migration
tenancy
permissions
policy
workflow
event
notification
API
UI
tests
```

and implement all of them according to OpenLoam conventions.

That predictability can become OpenLoam's moat.

---

# OpenLoam AI Benchmark

Maintain a permanent set of business-development tasks.

Example benchmark:

```text
Create Supplier
Add custom field
Add new permission
Create approval flow
Add dashboard metric
Create webhook
Add REST endpoint
Add scheduled job
Add notification
Modify existing workflow
```

## Metrics

| Metric | Initial Target |
|---|---:|
| Task completed | > 90% |
| Tests passing | > 95% |
| Architecture violations | < 5% |
| Human intervention | decreasing |
| Development speed vs vanilla Rails | +30–50% |

Do not market speed claims publicly until OpenLoam has enough real measurements to support them.

---

# Business Model

## Phase 1 — OSS as a Delivery Accelerator

Initially, OpenLoam does not need to monetize the developer community.

The first business model is:

```text
OpenLoam OSS
    ↓
GitHub / Rails community
    ↓
Companies that need custom systems
    ↓
Deliverists
    ↓
client implementations
```

OpenLoam should make Deliverists:

- faster
- more repeatable
- easier to differentiate from a typical software house

---

# Productized Service

A strong first commercial offer:

## OpenLoam Build Sprint

> We build your internal business platform on OpenLoam in 4–6 weeks.

Potential projects:

- CRM
- operations dashboard
- partner portal
- workflow automation
- admin backend
- custom B2B platform

The client receives custom software.

OpenLoam receives production testing and reusable improvements.

---

# Phase 2 — OpenLoam Enterprise

Once there are several real installations, introduce enterprise capabilities.

Potential paid features:

- SAML / SSO
- SCIM
- advanced permissions
- enterprise audit
- advanced security
- encryption
- advanced workflows
- compliance features
- LTS releases
- upgrade assistance
- architecture review
- production support

Possible packaging to test:

| Product | Shape |
|---|---|
| OpenLoam Core | Free / MIT |
| OpenLoam Enterprise | Annual subscription |
| Support | Retainer |
| Implementation | Per project |
| Architecture / AI customization | Per project |

These are packaging hypotheses, not offers. Nothing here is priced until
customer discovery says what the shape is worth.

---

# Distribution Strategy

## GitHub

Goal:

- attract Rails developers
- validate developer interest
- build credibility
- generate agency and enterprise leads

Do not optimize only for stars.

---

## Rails Agencies

Rails agencies may become excellent early adopters.

Pitch:

> Use OpenLoam as the foundation for your client applications.

Talk to at least:

> **15–20 Rails agencies**

during the first 90 days.

---

## Deliverists Clients

Use OpenLoam in real Deliverists work as early as possible.

That is the best validation loop:

```text
client work
    ↓
OpenLoam improvements
    ↓
open source
    ↓
developers
    ↓
inbound leads
    ↓
enterprise projects
    ↓
OpenLoam improvements
```

---

# 90-Day KPIs

| KPI | Goal |
|---|---:|
| Applications built with OpenLoam | 2 |
| Real client project | ≥ 1 |
| Development time reduction | ≥ 30% |
| Golden AI tasks | ≥ 20 |
| AI task completion | ≥ 80% |
| External developers installing OpenLoam | 10+ |
| Rails agency interviews | 15–20 |
| Design partners | 3–5 |
| Paid OpenLoam-based project | ≥ 1 |

One company paying for a real OpenLoam-based implementation is more valuable than 1,000 GitHub stars.

---

# Kill Criteria

After 90–120 days, answer three questions.

## 1. Does OpenLoam accelerate development?

Target:

> at least **25–30%**

If not, stop expanding features and fix the foundation.

---

## 2. Can an external Rails developer use OpenLoam without Deliverists support?

If not:

- improve DX
- improve documentation
- simplify installation
- reduce hidden conventions

---

## 3. Does anyone outside Deliverists want to build a real application with OpenLoam?

If not, OpenLoam may still be valuable as an internal accelerator.

That outcome can still make business sense if it materially improves how
Deliverists delivers client work.

---

# First Technical Milestone

The first OpenLoam milestone should not be CRM.

Start with:

```text
Organization
User
Membership
Permission
AuditEvent
```

Then define the first end-to-end AI benchmark:

> **An agent receives the prompt “Add Companies to OpenLoam” and independently builds a complete tenant-aware, permission-aware, audited CRUD with tests.**

Expected output:

- migration
- model
- tenancy rules
- permissions
- policy
- controller/actions
- views
- filters
- audit events
- API
- tests

If OpenLoam can make this workflow extremely reliable, it has the beginnings of a defensible product.

---

# Immediate Next Steps

## Week 1

- create repository
- define OpenLoam conventions
- implement Organization
- implement User
- implement Membership
- implement tenant scoping
- implement Permission
- implement AuditEvent

## Week 2

- add UI primitives
- add policies
- add events
- add notifications
- add custom fields
- add installation flow
- add documentation

## Week 3

- build first generators
- introduce AGENTS.md
- define first 10 golden AI tasks
- run first benchmarks

## Week 4

- stabilize core
- implement first complete resource through generators + AI
- publish internal demo
- decide what enters the CRM reference module

---

# Guiding Principle

For every feature, ask:

> **Does this make OpenLoam better at building business software repeatedly and predictably?**

If the answer is no, it probably does not belong in the core.

OpenLoam should remain small at the center and extensible at the edges.
