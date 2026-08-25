---
title: Events as the Decoupling Seam; Two Subscriber Tiers
description: Why the event bus has both an ephemeral and a durable subscriber tier.
nav_order: 5
---

# 0005. Events as the decoupling seam; two subscriber tiers

- Status: Accepted
- Date: 2026-08

## Context
Modules must react to each other without coupling (billing reacts to a rental
event; a webhook fires; a notification appears). And some reactions are cheap and
best-effort while others must not be lost. A single subscribe mechanism can't be
both "cheap and inline" and "durable and retried" honestly.

## Decision
One event bus (`domain.thing.happened`), two subscriber tiers with an explicit
contract: **ephemeral** (`Events.subscribe`, inline, best-effort, exception
propagates to the publisher) and **durable** (`DurableEvents.register`, persisted
per delivery, at-least-once with retry + dead-letter, exception contained in a job).

## Consequences
- Callers choose the guarantee deliberately; the docs state which to use when.
- Durability comes from a persisted delivery row + a redelivery sweep, not from
  trusting the queue — it survives a lost job.
- At-least-once means durable handlers must be idempotent (stated in the contract).
- Inbound webhooks join the same bus, so external events flow through one seam.
