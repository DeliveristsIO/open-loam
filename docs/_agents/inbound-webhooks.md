---
title: Inbound Webhooks
description: The public, HMAC-verified, replay-safe webhook receiver that republishes onto the event bus.
nav_order: 8
---

# Inbound webhooks — receiving events from external systems

The inbound sibling of `OpenLoam::Webhooks` (which delivers events *out*). An external
system POSTs to `/webhooks/:token`; OpenLoam verifies it, dedupes replays, records it,
and publishes it on the domain event bus so durable subscribers react.

## Setup (admin, manager-only)

`/admin/inbound_webhook_sources` → **New source**. OpenLoam generates:

- a **token** — the unguessable URL id: `POST https://your-app/webhooks/<token>`
- a **secret** — the HMAC-SHA256 key the sender signs each body with

Give the sender the URL and secret. Configure per source:

| Field | Meaning |
|---|---|
| `event_name` | what to publish on the bus (`domain.thing.happened`) |
| `signature_header` | where the signature arrives (default `X-OpenLoam-Signature`; GitHub uses `X-Hub-Signature-256`) |
| `delivery_id_header` | optional external delivery id for dedupe; blank ⇒ dedupe on a body hash |
| `timestamp_header` + `timestamp_tolerance` | optional freshness window (seconds; default 300) |

**Token identifies, signature authenticates.** The token in the URL will appear in
access logs and proxies — that's fine; it only selects the source. Forging a call
requires the secret. Rotate either from the admin at any time.

## The pipeline (`OpenLoam::InboundWebhooks.ingest`)

Checks run cheapest-and-least-trusting first, and **every auth failure returns a
bare `401`** so a sender can't probe which check failed (the reason is logged
server-side only):

1. body size → **413** (never HMAC a huge body; cap is `MAX_BYTES`, 1 MB)
2. token resolve → **404** (unknown or inactive source)
3. signature → **401** — constant-time HMAC-SHA256 over the **raw** body
4. timestamp → **401** — only if a `timestamp_header` is configured
5. dedupe → **200** — a replay is idempotent success, not an error
6. ingest + publish → **202**

The verified body is stored on a `OpenLoam::InboundWebhookDelivery` row; the published
event payload is **ids only** (`{ source_id:, delivery_id: }`), keeping it
scalar-clean like the outbound path. A subscriber reads the body from the row.

```ruby
OpenLoam::DurableEvents.register(key: "on_inbound", to: "billing.invoice.paid",
                             call: "Billing::ApplyPaymentHandler")
# handler reads OpenLoam::InboundWebhookDelivery.find(payload["delivery_id"]).payload_hash
```

## Guarantees

- **Replay resistance** is the `(source_id, external_id)` unique ledger: a replayed
  delivery hits the DB constraint and returns `200` without re-publishing. The
  timestamp window is **defense-in-depth only** — unless the sender signs the
  timestamp, a replayer can refresh an unsigned header; don't rely on it alone.
- **Race-safe:** two concurrent identical deliveries both try to insert; the loser
  catches `RecordNotUnique` and returns the idempotent `200`.
- **Retry-safe:** the row is created and the event published in one transaction —
  if the publish fails the row rolls back, so the sender's retry isn't deduped
  away.
- **Tenant isolation:** the token establishes the tenant (a blessed cross-tenant
  lookup, like `OpenLoam::ApiToken.authenticate`), and the controller resets
  `OpenLoam::Current` after every request.

## Notes / follow-ups

- The secret is stored plaintext, matching the outbound `OpenLoam::WebhookEndpoint`
  sibling; encrypting both at rest is a future hardening.
- Delivery rows accumulate — add a periodic prune for a high-volume source
  (a `open_loam:inbound:prune` task is the obvious follow-up).
