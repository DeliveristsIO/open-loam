---
title: Configuration
description: The real configuration surface of config/initializers/loam.rb — every setting loam:install ships, with syntax.
nav_order: 1
permalink: /reference/configuration/
---

# Configuration

`loam:install` generates `config/initializers/loam.rb` with every setting
below, commented out with an explanation, ready to uncomment. This page is
the same surface, without the prose — see the generated file itself
(`lib/generators/loam/install/templates/initializer.rb`) for the full
in-context comments.

## Roles and locales

```ruby
# Roles every tenant is expected to have — a registry your own seeding/admin
# code reads; Loam does not create memberships for you.
Loam.default_roles = %w[manager employee]

# Locales CONTENT translations (Loam::Translatable) may be authored in.
Loam.locales = %w[en]
```

## Feature-string permissions

A finer capability layer under the coarse role — orthogonal to roles
(`Loam::Membership`) and field-level policies (`Loam::Policy`). Deny-by-default;
`*` grants everything, a trailing `.*` is a prefix match.

```ruby
Loam::Permissions.configure do
  role :admin,   allow: "*"
  role :manager, allow: %w[equipment.* billing.read]
  role :clerk,   allow: %w[equipment.read]
end
```

Check with `Loam.can?("equipment.edit")`, `require_permission!("...")` in a
controller, or the `can?` view helper.

## App-wide setting defaults

```ruby
Loam.config_defaults = { "billing.currency" => "USD", "billing.net_terms" => 30 }
```

A key resolves, most specific first: per-tenant override → global row → this
declared default → `nil`. Read with `Loam::Configs.get(key)`; write with
`Loam::Configs.set(key, value)` (current tenant) or
`Loam::Configs.set(key, value, scope: :global)` (app-wide).

## Feature flags

```ruby
Loam.feature_defaults = {
  "beta_dashboard" => { default: false, description: "New dashboard, rolled out per tenant." }
}
```

`Loam::Features.on?(:beta_dashboard)`; guard a controller action with
`require_feature!(:beta_dashboard)` (404s when off), a view with
`feature_on?(:beta_dashboard)`.

## Security: MFA and auth throttling

Both resolved through `Loam::Configs` (global or per-tenant), not separate
settings:

```ruby
Loam::Configs.set("security.mfa_required_roles", ["manager"], scope: :global)

Loam::Configs.set("security.max_auth_attempts",   5,  scope: :global)  # default: 10
Loam::Configs.set("security.auth_window_minutes", 10, scope: :global)  # default: 15
```

## Encryption master key

```ruby
Loam::Encryption.master_key = ENV.fetch("LOAM_MASTER_KEY")
```

Per-tenant keys derive from it via HKDF — it must be stable and secret, never
committed. Only apps that actually `encrypts` a field need it. See
[Encryption at rest]({% link _agents/encryption.md %}).

## Event subscriptions and broadcast

Register subscriptions at file scope (not inside `to_prepare`, which would
double-register on reload):

```ruby
Loam::Events.subscribe("billing.subscription.renewed") do |name, payload|
  BillingMailer.renewal_receipt(payload[:id]).deliver_later
end

# Events pushed live to the browser over SSE — opt-in, default empty.
Loam.broadcast_events = [ "loam.notification.", "loam.progress." ]
```

## Scheduler

```ruby
Loam::Scheduler.register(key: "nightly_digest", name: "Nightly digest",
                          job_class: "DigestJob", schedule: "0 7 * * *", scope: "tenant")

# Only allowlisted job classes are schedulable (registered, or listed here).
Loam.schedulable_jobs = %w[DigestJob ReindexJob]
```

Wire a system cron to `bin/rails loam:scheduler:tick` every minute. See
[Scheduler]({% link _agents/scheduler.md %}).

## New-tenant defaults

```ruby
Loam.on_tenant_created do |tenant|
  # MUST be idempotent — bin/rails loam:sync re-runs this for every existing
  # tenant, which is how a default added later reaches tenants that already
  # exist. Use find_or_create_by!, never create!.
  Loam::Scheduler.sync_tenant(tenant)
end
```

## Search backend

```ruby
Loam::Search.driver = Loam::Search::TokenDriver   # default: LikeDriver
```

Every `searchable_by` declaration and `Model.search(q)` call site is
unchanged when switching drivers. Backfill once with `bin/rails loam:search:reindex`.

## Overrides (customization without forking)

```ruby
Loam::Overrides.disable(:widgets, "open_progress")
Loam::Overrides.replace(:widgets, "audit_recent") { |actor| { kind: "count", value: 0 } }
```

Only for Loam's own keyed registries (`:widgets`, `:broadcast_events`) —
override a view, controller, or route the standard Rails way instead.

## Response enrichers

```ruby
Loam::Enrichers.register("Equipment", key: "outstanding_balance", batch: ->(equipments) do
  totals = Invoice.where(equipment_id: equipments.map(&:id)).group(:equipment_id).sum(:balance)
  equipments.map(&:id).index_with { |id| totals.fetch(id, 0) }
end)
```

## Observability

```ruby
Loam::Telemetry.backend = ->(name, attributes, work) do
  OpenTelemetry.tracer_provider.tracer("loam").in_span(name, attributes: attributes.transform_keys(&:to_s)) { work.call }
end
```

By default, Loam's async hot paths (scheduler tick, durable event delivery,
inbound webhook ingest) emit `ActiveSupport::Notifications` events
(`"loam.span.*"`) whether or not a backend is configured.

## Related pages

- [Generators]({% link _reference/generators.md %})
- [The agent contract]({% link _agents/agent-contract.md %})
