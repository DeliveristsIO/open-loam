# Loam — Investor Overview

## Executive summary

Loam is an open-source foundation for building secure business software with
Ruby on Rails and AI coding agents. It provides the common infrastructure that
most business applications need—tenant isolation, access control, audit trails,
workflows, integrations, administration, and operational tooling—before a
product team starts writing its domain-specific features.

The premise is simple: teams should spend their time building the part of a
product that customers value, not repeatedly rebuilding the same application
plumbing. Loam turns that plumbing into one coherent, documented set of
conventions that both developers and AI agents can follow.

Loam is currently a working, tested prototype. It demonstrates the technical
foundation and the AI-assisted development workflow end to end. It has not yet
been validated in a production customer deployment, so the next milestone is a
measured real-world build rather than another large feature expansion.

## The problem

Business applications such as CRMs, operations portals, workflow systems, and
vertical SaaS products share a large amount of infrastructure:

- users, organizations, roles, and permissions;
- strict separation of each customer's data;
- audit history, approvals, and safe deletion;
- configurable fields, search, imports, and exports;
- APIs, webhooks, background jobs, and notifications;
- administration screens and operational controls.

These capabilities are essential, but they rarely differentiate the finished
product. Teams can spend months selecting libraries, reconciling architectural
decisions, and connecting these systems before they deliver their first unique
workflow.

AI coding agents can accelerate implementation, but they introduce a related
problem: an agent performs best when a codebase has clear rules and one obvious
way to add a feature. In an inconsistent application, the agent must guess how
tenancy, authorization, events, and testing are supposed to work. A wrong guess
can become a security defect.

## The Loam solution

Loam packages the shared foundation as a Rails engine, code generators, and an
agent-readable development contract. The foundation makes important decisions
once and applies them consistently across the application.

A developer or agent can generate a business entity and receive the model,
database migration, policy, admin screens, API controller, and guardrail tests
in the expected structure. The team then adds the business-specific workflow
instead of designing the surrounding infrastructure from scratch.

The result remains a normal Rails application. Loam is not a closed low-code
platform and does not hide the source code behind a proprietary builder. Teams
can inspect, test, extend, and operate the generated application using familiar
Rails practices.

## What Loam provides

### Secure application foundation

- Multi-tenant data isolation that raises when tenant context is missing rather
  than silently exposing a wider dataset.
- Role, policy, feature-level, and field-level permissions.
- Password authentication, multi-factor authentication, step-up authentication,
  lockout controls, and per-tenant OIDC single sign-on.
- Per-tenant field encryption, including exact-match blind indexes for selected
  encrypted values.
- Audit trails, record history, undo, soft deletion, and concurrent-edit
  protection.

### Flexible business modeling

- Generated domain entities with admin screens, APIs, policies, and tests.
- Runtime custom fields and managed dictionaries for configuration without a
  deployment.
- Declared workflows with state transitions and role-gated approvals.
- Content translations, saved views, configurable dashboards, comments, and
  attachments.
- Business rules that evaluate whitelisted data conditions and run a bounded set
  of safe actions without evaluating arbitrary code.

### Integration and operations

- Token-authenticated JSON APIs with automatically generated OpenAPI 3.1
  documentation.
- Signed outbound webhooks and replay-resistant inbound webhooks.
- An event backbone with fast in-process subscribers and durable, retryable
  delivery for important handlers.
- Notifications, live browser updates, recurring jobs, and long-running task
  progress.
- Policy-aware bulk CSV import and export.
- Pluggable search and response enrichment points for connecting modules without
  tightly coupling them.

### AI-native development controls

- A concise `AGENTS.md` contract tells an AI agent where code belongs and which
  security boundaries it must preserve.
- Generators provide a predictable interface for adding features.
- Structural guardrails test tenant isolation, authorization, and prohibited
  shortcuts.
- A human-approval primitive can stage an AI-proposed mutation for review before
  it changes business data.
- A repeatable golden-task benchmark measures whether agents complete common
  changes without violating architecture or access controls.

## What Loam can be used for

Loam is intended for multi-user business software in which permissions,
traceability, and operational workflows matter. Examples include:

| Product category | Example uses |
|---|---|
| Vertical SaaS | Industry-specific case management, compliance, field service, or scheduling products |
| Operations platforms | Work queues, approvals, exception handling, asset tracking, and internal operations |
| CRM and partner systems | Account management, pipelines, partner portals, and customer onboarding |
| ERP-like applications | Inventory, purchasing, fulfillment, and other connected business workflows |
| Internal tools | Secure administrative consoles over company data and processes |
| Agency delivery | A repeatable base for building and maintaining client business applications |
| AI-assisted products | Applications where agents add features or propose controlled changes to business records |

Loam is a foundation, not a finished CRM, ERP, accounting package, or ecommerce
product. Those can be built as domain products or reusable packs on top of it.

## How it works

Loam sits between Rails and the product's business-specific code:

```text
Product workflows and domain features
                 ↓
Loam conventions, security, admin, events, and integrations
                 ↓
Ruby on Rails
```

The core isolation model is tenant-scoped: business records belong to a tenant,
and ordinary queries require an active tenant context. Policies control which
records and fields an actor can access. Changes are audited, and domain events
connect notifications, webhooks, rules, and durable background processing.

Because these concerns share the same conventions, a feature does not need to
reimplement them independently. That consistency is also what makes the system
legible to an AI agent.

## Why the approach is differentiated

Loam combines three properties that are usually offered separately:

1. A broad business-application foundation rather than a narrow starter
   template.
2. Rails conventions and readable generated code rather than a proprietary
   runtime or visual builder.
3. Explicit AI-agent instructions, guardrails, benchmarks, and approval controls
   rather than treating AI-generated code as ordinary unstructured output.

The defensible value is expected to accumulate in the conventions, test corpus,
real-world implementation knowledge, and reusable domain packs—not merely in the
number of framework modules.

## Current evidence

As of 2026-08-22:

- The repository contains a working Rails engine and a complete equipment-rental
  demonstration application.
- The demo suite passes 454 tests and 1,534 assertions with no failures or
  errors.
- The generator harness builds fresh Rails applications, installs Loam,
  generates entities, migrates databases, and exercises the generated result.
- Recorded golden-task evaluation completed 10 out of 10 tasks without tenant
  isolation or authorization violations; a recorded vanilla-Rails control
  preserved isolation in 1 out of 10 tasks under the same prompts. This is an
  internal benchmark, not yet independent or production evidence.
- Adversarial reviews found security defects in earlier iterations, and the
  fixes were preserved as regression tests.

The project should still be evaluated as a prototype. Its breadth and tests show
that the architecture is coherent; they do not yet prove customer demand,
production reliability at scale, or a measurable reduction in delivery cost.

## Business model under consideration

The proposed model is open core:

- Loam Core remains MIT-licensed and self-hostable, supporting adoption and
  ecosystem growth.
- Team and enterprise offerings can package advanced governance, compliance,
  analytics, and support.
- A managed offering can serve teams that want the foundation without operating
  it themselves.
- A marketplace can distribute paid domain packs, implementation recipes, and
  specialized agent packs.

This model is a direction, not a launched commercial offering. Pricing,
packaging, and willingness to pay still require customer discovery.

## Near-term plan

The roadmap prioritizes validation over feature count:

1. Build one real business process with Loam and AI assistance.
2. Measure delivery time, human intervention, test outcomes, and architecture
   violations against a credible conventional-Rails baseline.
3. Use the observed workflow to decide which AI tools and integration surfaces
   matter, including whether an MCP server is justified.
4. Turn the validated domain into a reference module and adoption story.
5. Interview target users and test commercial packaging before investing in a
   larger hosted or enterprise product.

The current product plan uses a target of at least 25–30% delivery-time reduction
for the first measured build as a decision threshold. Until that experiment is
complete, it should be treated as a target rather than an achieved result.

## Key risks and how they are addressed

| Risk | Current response |
|---|---|
| No production validation yet | Make a measured dogfood deployment the highest-priority milestone |
| Broad prototype surface | Freeze public conventions, keep modules small, and validate the highest-value paths first |
| Security sensitivity of multi-tenant software | Enforce isolation structurally, perform adversarial reviews, and retain exploit regression tests |
| AI output can be unpredictable | Use generators, explicit agent contracts, guardrails, benchmarks, and human approval for sensitive mutations |
| Framework adoption friction | Stay compatible with normal Rails code and offer the core under the MIT license |
| Commercial model is unproven | Conduct customer discovery and packaging tests before scaling enterprise development |

## The investment case

Loam is a bet that AI-assisted software delivery needs more than a capable model:
it needs an application foundation designed to make correct implementation
predictable. If validated, Loam can help product teams and agencies deliver
serious business software faster while retaining readable code, human control,
and security boundaries.

Investment at this stage would primarily fund validation: real deployments,
measurement, customer discovery, production hardening, and the first reusable
domain pack. The central question is no longer whether the foundation can be
built—the prototype demonstrates that it can—but whether it produces a large,
repeatable economic advantage in real projects.

## Further reading

- [README](README.md) — product capabilities and quick start
- [Concept and positioning](docs/_guides/concept.md) — product thesis and market position
- [Architecture](docs/_guides/architecture.md) — technical design and module boundaries
- [Roadmap](ROADMAP.md) — shipped work, open priorities, and validation plan
- [Backward-compatibility contract](BACKWARD_COMPATIBILITY.md) — stable public surfaces
- [Getting started](docs/_guides/getting-started.md) — hands-on walkthrough
