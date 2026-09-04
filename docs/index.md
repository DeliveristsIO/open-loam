---
layout: home
title: A Rails foundation for AI-built business apps
description: OpenLoam is a Rails starter kit for business apps — multi-tenancy, permissions, audit trails, and an event bus already built in, so you skip months of plumbing and start on real features. It's also AI-native, with human-approval gates before any agent write takes effect.
permalink: /
hero:
  name: OpenLoam
  text: A Rails foundation for AI-built business apps
  tagline: Multi-tenancy, roles and permissions, audit trails, and an event bus — already built in, so you skip months of plumbing and build the actual business. AI agents can extend it safely too — every write they propose waits for human approval before it takes effect.
  code_panel:
    - title: Install
      link: /getting-started/
      code: |
        ```bash
        bin/rails g open_loam:install
        bin/rails g open_loam:entity Equipment name:string daily_rate:decimal --domain rental
        ```
    - title: Tenant isolation
      link: /foundation/tenant-isolation/
      code: |
        ```ruby
        class Equipment < OpenLoam::TenantRecord
          include OpenLoam::Auditable
          include OpenLoam::Eventful
        end

        Equipment.count   # => raises OpenLoam::MissingTenantError, no context
        ```
    - title: Field-level permissions
      link: /foundation/authorization/
      code: |
        ```ruby
        class EquipmentPolicy < OpenLoam::Policy
          field :daily_rate, writable: [:manager]
        end
        ```
    - title: AI approval gate
      link: /agents/confirm-mode/
      code: |
        ```ruby
        OpenLoam::PendingActions.stage(
          summary: "Raise Excavator's daily rate",
          on: equipment, action: :update, changes: { daily_rate: 1050 }
        )
        ```
    - title: MCP server
      link: /agents/mcp/
      code: |
        ```bash
        bin/rails open_loam:mcp:serve
        # list_entities / describe_entity / query_entity / stage_write
        ```
    - title: Golden tasks
      link: /agents/golden-tasks/
      code: |
        ```text
        Tenant isolation enforced (HTTP probe)
          OpenLoam + AI:    10/10
          Vanilla + AI:  1/10

        One internal run, same prompts, same model.
        Method and caveats published in full.
        ```
  actions:
    - theme: brand
      text: Get started
      link: /getting-started/
    - theme: alt
      text: How OpenLoam works
      link: /foundation/overview/
    - theme: alt
      text: View on GitHub
      link: https://github.com/DeliveristsIO/open-loam

features:
  - icon: "🏢"
    title: Multi-tenancy, structurally
    details: "Tenant isolation baked into every query, job, and event via [`OpenLoam::TenantRecord`](/foundation/tenant-isolation/). A missing tenant context raises — it never silently widens a query."
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
    details: "[AGENTS.md is the contract](/agents/agent-contract/); [`open_loam:entity`](/reference/generators/) is the interface; an [MCP server](/agents/mcp/) exposes tenant-scoped, policy-aware reads and human-approved writes."
  - icon: "📊"
    title: Benchmarked, caveats published
    details: "In one internal run of the [golden-tasks benchmark](/agents/golden-tasks/), tenant isolation held 10/10 on OpenLoam apps versus 1/10 on vanilla Rails — same prompts, same model, protocol pre-registered. A single run, not yet repeated or independently reproduced, and the page says so."
---
