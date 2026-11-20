---
title: Outbound webhooks
description: "Ledger, retries, signatures and host hooks for OpenLoam's outbound webhooks."
nav_order: 3
---

# Outbound webhooks

Every OpenLoam event is offered to the tenant's active `OpenLoam::WebhookEndpoint`s.
A matching endpoint gets one `OpenLoam::WebhookDelivery` row, written in the
publishing transaction; `OpenLoam::WebhookDeliveryJob` is enqueued after commit.

## Guarantee

At-least-once, unordered. Receivers dedupe by the `-Event-Id` header (shared by
every endpoint and every retry of one event). The body may be rebuilt on a retry,
so it can reflect newer data than the first attempt.

## Lifecycle

`pending -> sending -> succeeded | failed`, back to `pending` with
`next_attempt_at` for a retry, `cancelled` when the endpoint is off or the body
builder raises `OpenLoam::Webhooks::SkipDelivery`.

| Answer | Outcome |
|---|---|
| 2xx | succeeded; endpoint `consecutive_failures` reset |
| 408, 429, 5xx, network error, timeout, DNS failure (`OutboundUrl::UnresolvableError`) | retried on `retry_schedule` (default 1m, 5m, 30m, 2h, 6h, 12h, 24h, ±10% jitter); `Retry-After` seconds win, capped at 1h; after the last step the row is `failed` |
| 410 | failed; endpoint disabled (`gone`) |
| other 1xx/3xx/4xx | failed, no retry (redirects are never followed) |
| URL resolves to a non-public address | failed; endpoint disabled (`blocked_url`) |

The transport sends `Accept-Encoding: identity` and keeps at most 512 bytes of the
response (`response_excerpt`).

`disable_after_failures` (default 50) failed attempts in a row disable the endpoint
and publish `open_loam.webhook.endpoint_disabled` (`endpoint_id`, `reason`).
`WebhookEndpoint#enable!` switches it back on. An error raised by that bookkeeping
(for example by a host subscriber to the event) propagates out of the job; it is
not retried as a delivery failure.

## Headers

`<prefix>` is `X-OpenLoam` unless `OpenLoam::Webhooks.header_prefix` is set.

| Header | Value |
|---|---|
| `<prefix>-Event` | event name |
| `<prefix>-Event-Id` | UUID per event |
| `<prefix>-Delivery` | `whd_...` per (event, endpoint) |
| `<prefix>-Timestamp` | Unix seconds of this attempt |
| `<prefix>-Signature` | `sha256=HMAC-SHA256(secret, body)` — frozen 0.3.0 format |
| `<prefix>-Signature-V2` | `t=<ts>,v1=HMAC-SHA256(secret, "<ts>.<body>")`, one `v1=` per signing secret during rotation |

Verify V2: split on `,`, reject when `|now - t| > 300`, compare each `v1` in constant
time. `OpenLoam::Webhooks.verify_v2(header, body, secret)` is the reference.

## Host configuration

```ruby
OpenLoam::Webhooks.header_prefix = "X-Acme"
OpenLoam::Webhooks.user_agent = "Acme-Webhooks/1.0"
OpenLoam::Webhooks.require_https = true
OpenLoam::Webhooks.allowed_ports = [ 443 ]
OpenLoam::Webhooks.encrypt_secrets = true        # needs OpenLoam::Encryption.master_key
OpenLoam::Webhooks.test_event_name = "acme.webhook.test"
OpenLoam::Webhooks.delivery_retention = 30.days  # nil keeps rows forever
OpenLoam::Webhooks.body_builder = Acme::WebhookBody # #call(endpoint:, delivery:) -> Hash
```

Endpoints follow one pattern (`event_pattern`) or several (`event_patterns`), and
carry a host-owned `metadata` json (`#settings`). `send_test!(endpoint)`,
`redeliver!(delivery)` and `endpoint.rotate_secret!` (old secret valid for
`secret_rotation_grace`, default 24h) are the operator actions. `redeliver!`
applies only to finished deliveries (succeeded, failed, cancelled) and resets
`attempts` to 0, so the full retry schedule runs again.

## Sweep

`OpenLoam::WebhookSweepJob` is registered with the scheduler (every 60 s, per
tenant). An app that does not tick `OpenLoam::Scheduler` runs
`OpenLoam::WebhookSweepJob.perform_later` (no arguments) from its own cron every
minute; it fans out to tenants with work (`Webhooks.tenant_ids_needing_sweep`).
