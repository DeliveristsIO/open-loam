---
layout: home
title: A Rails foundation for AI-built business apps
description: Loam is a Rails starter kit for business apps — multi-tenancy, permissions, audit trails, and an event bus already built in, so you skip months of plumbing and start on real features. It's also AI-native, with human-approval gates before any agent write takes effect.
permalink: /
hero:
  name: Loam
  text: A Rails foundation for AI-built business apps
  tagline: Multi-tenancy, roles and permissions, audit trails, and an event bus — already built in, so you skip months of plumbing and build the actual business. AI agents can extend it safely too — every write they propose waits for human approval before it takes effect.
  code_panel:
    - title: Install
      link: /getting-started/
      code: |
        ```bash
        bin/rails g loam:install
        bin/rails g loam:entity Equipment name:string daily_rate:decimal --domain rental
        ```
    - title: Tenant isolation
      link: /foundation/tenant-isolation/
      code: |
        ```ruby
        class Equipment < Loam::TenantRecord
          include Loam::Auditable
          include Loam::Eventful
        end

        Equipment.count   # => raises Loam::MissingTenantError, no context
        ```
    - title: Field-level permissions
      link: /foundation/authorization/
      code: |
        ```ruby
        class EquipmentPolicy < Loam::Policy
          field :daily_rate, writable: [:manager]
        end
        ```
    - title: AI approval gate
      link: /agents/confirm-mode/
      code: |
        ```ruby
        Loam::PendingActions.stage(
          summary: "Raise Excavator's daily rate",
          on: equipment, action: :update, changes: { daily_rate: 1050 }
        )
        ```
    - title: MCP server
      link: /agents/mcp/
      code: |
        ```bash
        bin/rails loam:mcp:serve
        # list_entities / describe_entity / query_entity / stage_write
        ```
    - title: Golden tasks
      link: /agents/golden-tasks/
      code: |
        ```text
        Tenant isolation enforced (HTTP probe)
          Loam + AI:    10/10
          Vanilla + AI:  1/10
        ```
  actions:
    - theme: brand
      text: Get started
      link: /getting-started/
    - theme: alt
      text: How Loam works
      link: /foundation/overview/
    - theme: alt
      text: View on GitHub
      link: https://github.com/DeliveristsIO/open-loam

features:
  - icon: "🏢"
    title: Multi-tenancy, structurally
    details: "Tenant isolation baked into every query, job, and event via [`Loam::TenantRecord`](/foundation/tenant-isolation/). A missing tenant context raises — it never silently widens a query."
  - icon: "🔐"
    title: Authorization, not just permissions
    details: "Roles, [policies, and field-level write access](/foundation/authorization/) declared once. Plus wildcard [feature-string permissions](/getting-started/) (`equipment.*`), deny-by-default."
  - icon: "📡"
    title: A real event backbone
    details: "[Ephemeral and durable subscribers](/agents/events/) on one domain event bus — at-least-once delivery, dead-letter, redelivery sweep for the durable tier."
  - icon: "🚧"
    title: Guardrails, not guidelines
    details: "[Structural tests](/agents/guardrails/) fail the build on a missing tenant scope, a stray `.unscoped`, or an oversized AGENTS.md — before a human has to catch it in review."
  - icon: "🤖"
    title: Built for coding agents
    details: "[AGENTS.md is the contract](/agents/agent-contract/); [`loam:entity`](/reference/generators/) is the interface; an [MCP server](/agents/mcp/) exposes tenant-scoped, policy-aware reads and human-approved writes."
  - icon: "📊"
    title: Measured, not asserted
    details: "The [golden-tasks benchmark](/agents/golden-tasks/) found tenant isolation held 10/10 on Loam apps versus 1/10 on hand-rolled vanilla Rails, same prompts, same model — internal results, disclosed as such."
---
