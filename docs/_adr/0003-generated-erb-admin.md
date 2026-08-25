---
title: A Generated ERB Admin, Not a Dependency
description: Why the admin surface is a generated ERB console rather than a third-party admin gem.
nav_order: 3
---

# 0003. A generated ERB admin, not a dependency

- Status: Accepted
- Date: 2026-08

## Context
Business apps need an admin back-office. Options: adopt a framework (Avo,
Administrate) or generate plain Rails screens. A framework is powerful but is a
large dependency an agent must learn, and it abstracts the very code we want to
stay legible.

## Decision
Generate a Hotwire-free ERB admin console from the entity generator — CRUD,
comments, attachments, search, filtering, pagination, permission-aware — as
ordinary, readable Rails the app owns.

## Consequences
- Zero admin dependency; an agent reads and extends normal controllers/views.
- More generated code to maintain in templates, and fewer batteries than a mature
  admin gem.
- Avo stays an evaluated alternative behind the same generated surface; the
  decision is revisitable per real usage.
