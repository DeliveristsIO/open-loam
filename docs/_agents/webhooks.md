---
title: Outbound webhooks
description: "Ledger, retries, signatures and host hooks for OpenLoam's outbound webhooks."
nav_order: 3
---

# Outbound webhooks

Every OpenLoam event is offered to the tenant's active `OpenLoam::WebhookEndpoint`s.
A matching endpoint gets one `OpenLoam::WebhookDelivery` row, written where the
event is dispatched; `OpenLoam::WebhookDeliveryJob` is enqueued after commit.

When the rows are written depends on how the event was published:

- Lifecycle events from `OpenLoam::Eventful` (`*.created`, `*.updated`, ...) are
  published after the change commits, so dispatch runs after commit and the
  ledger rows are written in their own statement after the change. A crash in
  between loses those deliveries.
- An explicit `OpenLoam::Events.publish` inside a transaction dispatches inline:
  the rows are written in that transaction and commit or roll back with it.

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
| other 1xx/3xx/4xx | failed, no retry (redirects are never followed); counts toward the endpoint's failure streak |
| URL resolves to a non-public address | failed; endpoint disabled (`blocked_url`) |

The transport sends `Accept-Encoding: identity`, ignores `http_proxy`, and keeps
at most 512 bytes of the response (`response_excerpt`, scrubbed to valid UTF-8
without NUL). Each socket operation is bounded by `OpenLoam::Webhooks.timeout`
(default 10 s) and the whole request by 3 x `timeout` (30 s); keep that below
`stuck_after` (default 5 min), or the sweep may resend a delivery still in flight.

An endpoint is disabled for failing only when BOTH hold: `disable_after_failures`
(default 50) failed attempts in a row, AND the streak started at least
`disable_after_duration` (default 24h, tracked in `failing_since`) ago — a short
outage under heavy traffic does not switch it off. 410 and a blocked URL disable
at once. Disabling publishes `open_loam.webhook.endpoint_disabled` (`endpoint_id`,
`reason`) exactly once. `WebhookEndpoint#enable!` switches it back on and clears
the streak. An error raised by that bookkeeping
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
| `<prefix>-Signature` | `sha256=HMAC-SHA256(secret, body)` — frozen 0.3.0 format, current secret only |
| `<prefix>-Signature-V2` | `t=<ts>,v1=HMAC-SHA256(secret, "<ts>.<body>")`, one `v1=` per signing secret during rotation |

Verify V2: split on `,`, reject when `|now - t| > 300`, compare each `v1` in constant
time. `OpenLoam::Webhooks.verify_v2(header, body, secret)` is the reference.

The v1 `-Signature` is computed with the current secret only. A receiver that
verifies only v1 breaks the moment the secret is rotated; the grace period helps
only receivers that verify `-Signature-V2`.

## Host configuration

```ruby
OpenLoam::Webhooks.header_prefix = "X-Acme"
OpenLoam::Webhooks.user_agent = "Acme-Webhooks/1.0"
OpenLoam::Webhooks.require_https = true
OpenLoam::Webhooks.allowed_ports = [ 443 ]
OpenLoam::Webhooks.encrypt_secrets = true        # needs OpenLoam::Encryption.master_key
OpenLoam::Webhooks.test_event_name = "acme.webhook.test"
OpenLoam::Webhooks.delivery_retention = 30.days  # nil keeps rows forever
OpenLoam::Webhooks.disable_after_failures = 50
OpenLoam::Webhooks.disable_after_duration = 24.hours
OpenLoam::Webhooks.body_builder = Acme::WebhookBody # #call(endpoint:, delivery:) -> Hash
```

Endpoints follow one pattern (`event_pattern`) or several (`event_patterns`), and
carry a host-owned `metadata` json (`#settings`). `send_test!(endpoint)`,
`redeliver!(delivery)` and `endpoint.rotate_secret!` (old secret valid for
`secret_rotation_grace`, default 24h) are the operator actions.

A `body_builder` should raise `OpenLoam::Webhooks::SkipDelivery` when the record it
describes is gone (erased): the delivery is cancelled. Any other error it (or the
header building) raises is retried on the schedule without counting against the
endpoint's health — a bug in the host is not the receiver's failure. `redeliver!`
applies only to finished deliveries (succeeded, failed, cancelled) and resets
`attempts` to 0, so the full retry schedule runs again.

## Sweep

`OpenLoam::WebhookSweepJob` is registered with the scheduler (every 60 s, per
tenant). An app that does not tick `OpenLoam::Scheduler` runs
`OpenLoam::WebhookSweepJob.perform_later` (no arguments) from its own cron every
minute; it fans out to tenants with work (`Webhooks.tenant_ids_needing_sweep`).

A row stuck in `sending` longer than `stuck_after` goes back to `pending`; one that
has already used up the retry schedule (`attempts > retry_schedule.size`) is marked
`failed` with `last_error: "stuck"` instead, so a persistent error after the send
cannot resend it forever.
