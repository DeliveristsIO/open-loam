---
title: Events — Ephemeral vs Durable
description: "The two-tier subscriber contract (L-706): in-process ephemeral subscribers and persisted, retried durable ones."
nav_order: 2
---

# Events — ephemeral vs durable subscribers (the L-706 contract)

Loam has one domain event bus and **two ways to subscribe**. They are not
interchangeable; picking the wrong one is a correctness bug, so the contract is
explicit.

## Publishing (unchanged)

```ruby
Loam::Events.publish("billing.invoice.paid", { id: invoice.id })
```

Names are `domain.thing.happened`. Publishing stamps `tenant_id` and `actor_id`
onto the payload. Entities that `include Loam::Eventful` publish
`created`/`updated`/`destroyed` automatically on `after_*_commit`.

Payloads are **ids and scalars by convention, never records** — the same
primitive crosses into a webhook body or a durable delivery row.

## Ephemeral subscribers — `Loam::Events.subscribe`

```ruby
Loam::Events.subscribe("billing.") { |name, payload| ... }   # a whole domain
Loam::Events.subscribe("billing.invoice.paid") { |name, payload| ... } # one event
```

- Runs **inline in the publisher's thread**, synchronously.
- **Best-effort, no persistence, no retry.**
- An exception in the block **propagates into whatever published the event** —
  it can fail the request that triggered it.

Use it for cheap in-process fan-out where losing the callback on a crash is
fine and where you *want* the work inline. The webhook dispatcher is the
canonical example: it subscribes to every event and enqueues its own delivery
jobs.

## Durable subscribers — `Loam::DurableEvents.register`

```ruby
# in an initializer (boot-time, trusted code)
Loam::DurableEvents.register(
  key:  "billing_grant_access",         # stable id, stored on every delivery row
  to:   "billing.invoice.paid",         # event name, or "billing." for a domain
  call: "Billing::GrantAccessHandler"   # responds to .call(event_name, payload)
)
```

On publish, for each matching durable subscriber Loam:

1. **commits a `Loam::EventDelivery` row** in the event's tenant (status
   `pending`), then
2. enqueues `Loam::EventDeliveryJob` to run the handler.

The job resolves the handler **from the registry by key** and calls it. On
success the row is `delivered`; on failure the row records the error, increments
`attempts`, and sets `next_attempt_at` to a backoff. Past `MAX_ATTEMPTS` (5) the
row is parked **`dead`** for an operator.

### The guarantee

**At-least-once, unordered. Handlers MUST be idempotent** — a retry or the sweep
can deliver the same event twice. If your handler grants access, granting twice
must be harmless; if it must run exactly once, dedupe inside the handler (e.g.
keyed on the payload id).

**Durability is of _delivery_, not _capture_.** An event whose process dies
between the `after_commit` and the `publish` leaves no row and is lost — exactly
as today. This feature makes what *was* published arrive; it cannot resurrect
what was never published.

### The sweep is the real durability

`perform_later` at publish is only an accelerator. The durability comes from
`Loam::EventRedeliverySweepJob` — registered per tenant on a 5-minute schedule —
which re-enqueues any `pending` row whose backoff has elapsed. So a delivery
survives a lost queue message, a crashed worker, or an async adapter that runs
the job before the creating transaction commits (the job no-ops on the invisible
row; the sweep picks it up once it commits).

### Dead-letter

`Admin::EventDeliveriesController` (`/admin/event_deliveries`, manager-only)
lists `dead` deliveries with the last error and a **Requeue** button that re-arms
the row to `pending` and nudges a job — the fix-the-handler-then-retry loop.

## Security

A durable handler is resolved from the **in-memory registry**, populated at boot
from trusted code — **never `constantize`d from the stored row**. If the key is
unknown at delivery time (the subscriber was removed since enqueue), the row is
parked `dead`; an arbitrary class is never executed off a database value. This
is the same posture as the scheduler's `job_class` allowlist.

Nil-tenant events are **not** durably delivered (the same decision the webhook
dispatcher makes) — durable delivery is a tenant-scoped guarantee.

## Choosing

| | Ephemeral | Durable |
|---|---|---|
| API | `Events.subscribe` | `DurableEvents.register` |
| Runs | inline, sync | background job |
| Survives a crash | no | yes (row + sweep) |
| Retry | no | yes, backoff → dead-letter |
| Exception | propagates to publisher | contained in the job |
| Ordering | publish order, inline | unordered |
| Use for | cheap in-process fan-out | side effects that must not be lost |
