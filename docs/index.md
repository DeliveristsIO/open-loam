---
layout: home
title: AI-native Rails business foundation
description: Loam pre-decides the 80% every business app shares — multi-tenancy, roles and field-level permissions, audit trails, a domain event bus, an admin surface — so humans and AI agents build the 20% that's the actual business.
permalink: /
hero:
  name: Loam
  text: The fertile Rails foundation where AI agents grow business software
  tagline: Multi-tenancy, roles and permissions, an event backbone, custom entities, audit trails, and an admin surface come already decided — as conventions, not choices you re-litigate on every project.
  code_panel:
    - title: Install
      link: /getting-started/
      code: |
        ```bash
        bin/rails g loam:install
        bin/rails g loam:entity Equipment name:string daily_rate:decimal --domain rental
        ```
    - title: Tenant isolation
      link: /agents/
      code: |
        ```ruby
        class Equipment < Loam::TenantRecord
          include Loam::Auditable
          include Loam::Eventful
        end

        Equipment.count   # => raises Loam::MissingTenantError, no context
        ```
    - title: Field-level permissions
      link: /getting-started/
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
    - title: Domain events
      link: /agents/events/
      code: |
        ```ruby
        Loam::DurableEvents.register(
          key: "notify_managers",
          to: "rental.damage_report.approve",
          call: ->(payload) { Loam::Notifications.notify_role(:manager, ...) }
        )
        ```
  actions:
    - theme: brand
      text: Get started
      link: /getting-started/
    - theme: alt
      text: Architecture
      link: /architecture/
    - theme: alt
      text: View on GitHub
      link: https://github.com/DeliveristsIO/open-loam

features:
  - icon: "🏢"
    title: Multi-tenancy, structurally
    details: "Tenant isolation baked into every query, job, and event via [`Loam::TenantRecord`](/architecture/). A missing tenant context raises — it never silently widens a query."
  - icon: "🔐"
    title: Permissions & auth
    details: "Roles, policies, and field-level write access declared once. Plus wildcard [feature-string permissions](/getting-started/) (`equipment.*`), deny-by-default."
  - icon: "📡"
    title: A real event backbone
    details: "[Ephemeral and durable subscribers](/agents/events/) on one domain event bus — at-least-once delivery, dead-letter, redelivery sweep for the durable tier."
  - icon: "🚦"
    title: An AI approval gate
    details: "An agent under [confirm-mode](/agents/confirm-mode/) stages a write instead of committing it; a manager approves before anything executes."
  - icon: "🤖"
    title: MCP server included
    details: "[Expose Loam to an agent](/agents/mcp/): tenant-scoped reads and staged, human-approved writes — the same gates the rest of the app obeys."
  - icon: "🧾"
    title: Audit, undo, encryption
    details: "Every change recorded by default; the audit trail doubles as an [undo stack](/agents/undo/); [per-tenant AES-256-GCM encryption](/agents/encryption/) for regulated fields."
---
