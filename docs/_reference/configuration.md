---
title: Configuration
description: The real configuration surface of config/initializers/open_loam.rb — every setting open_loam:install ships, with syntax.
nav_order: 1
permalink: /reference/configuration/
---

# Configuration

`open_loam:install` generates `config/initializers/open_loam.rb` with every setting
below, commented out with an explanation, ready to uncomment. This page is
the same surface, without the prose — see the generated file itself
(`lib/generators/open_loam/install/templates/initializer.rb`) for the full
in-context comments.

## Roles and locales

```ruby
# Roles every tenant is expected to have — a registry your own seeding/admin
# code reads; OpenLoam does not create memberships for you.
OpenLoam.default_roles = %w[manager employee]

# Locales CONTENT translations (OpenLoam::Translatable) may be authored in.
OpenLoam.locales = %w[en]
```

## Feature-string permissions

A finer capability layer under the coarse role — orthogonal to roles
(`OpenLoam::Membership`) and field-level policies (`OpenLoam::Policy`). Deny-by-default;
`*` grants everything, a trailing `.*` is a prefix match.

```ruby
OpenLoam::Permissions.configure do
  role :admin,   allow: "*"
  role :manager, allow: %w[equipment.* billing.read]
  role :clerk,   allow: %w[equipment.read]
end
```

Check with `OpenLoam.can?("equipment.edit")`, `require_permission!("...")` in a
controller, or the `can?` view helper.

## App-wide setting defaults

```ruby
OpenLoam.config_defaults = { "billing.currency" => "USD", "billing.net_terms" => 30 }
```

A key resolves, most specific first: per-tenant override → global row → this
declared default → `nil`. Read with `OpenLoam::Configs.get(key)`; write with
`OpenLoam::Configs.set(key, value)` (current tenant) or
`OpenLoam::Configs.set(key, value, scope: :global)` (app-wide).

## Feature flags

```ruby
OpenLoam.feature_defaults = {
  "beta_dashboard" => { default: false, description: "New dashboard, rolled out per tenant." }
}
```

`OpenLoam::Features.on?(:beta_dashboard)`; guard a controller action with
`require_feature!(:beta_dashboard)` (404s when off), a view with
`feature_on?(:beta_dashboard)`.

## Security: MFA and auth throttling

Both resolved through `OpenLoam::Configs` (global or per-tenant), not separate
settings:

```ruby
OpenLoam::Configs.set("security.mfa_required_roles", ["manager"], scope: :global)

OpenLoam::Configs.set("security.max_auth_attempts",   5,  scope: :global)  # default: 10
OpenLoam::Configs.set("security.auth_window_minutes", 10, scope: :global)  # default: 15
```

## Encryption master key

```ruby
OpenLoam::Encryption.master_key = ENV.fetch("OPEN_LOAM_MASTER_KEY")
```

Per-tenant keys derive from it via HKDF — it must be stable and secret, never
committed. Only apps that actually `encrypts` a field need it. See
[Encryption at rest]({% link _agents/encryption.md %}).

## Event subscriptions and broadcast

Register subscriptions at file scope (not inside `to_prepare`, which would
double-register on reload):

```ruby
OpenLoam::Events.subscribe("billing.subscription.renewed") do |name, payload|
  BillingMailer.renewal_receipt(payload[:id]).deliver_later
end

# Events pushed live to the browser over SSE — opt-in, default empty.
OpenLoam.broadcast_events = [ "open_loam.notification.", "open_loam.progress." ]
```

## Scheduler

```ruby
OpenLoam::Scheduler.register(key: "nightly_digest", name: "Nightly digest",
                          job_class: "DigestJob", schedule: "0 7 * * *", scope: "tenant")

# Only allowlisted job classes are schedulable (registered, or listed here).
OpenLoam.schedulable_jobs = %w[DigestJob ReindexJob]
```

Wire a system cron to `bin/rails open_loam:scheduler:tick` every minute. See
[Scheduler]({% link _agents/scheduler.md %}).

## New-tenant defaults

```ruby
OpenLoam.on_tenant_created do |tenant|
  # MUST be idempotent — bin/rails open_loam:sync re-runs this for every existing
  # tenant, which is how a default added later reaches tenants that already
  # exist. Use find_or_create_by!, never create!.
  OpenLoam::Scheduler.sync_tenant(tenant)
end
```

## Search backend

```ruby
OpenLoam::Search.driver = OpenLoam::Search::TokenDriver   # default: LikeDriver
```

Every `searchable_by` declaration and `Model.search(q)` call site is
unchanged when switching drivers. Backfill once with `bin/rails open_loam:search:reindex`.

## Overrides (customization without forking)

```ruby
OpenLoam::Overrides.disable(:widgets, "open_progress")
OpenLoam::Overrides.replace(:widgets, "audit_recent") { |actor| { kind: "count", value: 0 } }
```

Only for OpenLoam's own keyed registries (`:widgets`, `:broadcast_events`) —
override a view, controller, or route the standard Rails way instead.

## Response enrichers

```ruby
OpenLoam::Enrichers.register("Equipment", key: "outstanding_balance", batch: ->(equipments) do
  totals = Invoice.where(equipment_id: equipments.map(&:id)).group(:equipment_id).sum(:balance)
  equipments.map(&:id).index_with { |id| totals.fetch(id, 0) }
end)
```

## Observability

```ruby
OpenLoam::Telemetry.backend = ->(name, attributes, work) do
  OpenTelemetry.tracer_provider.tracer("open_loam").in_span(name, attributes: attributes.transform_keys(&:to_s)) { work.call }
end
```

By default, OpenLoam's async hot paths (scheduler tick, durable event delivery,
inbound webhook ingest) emit `ActiveSupport::Notifications` events
(`"open_loam.span.*"`) whether or not a backend is configured.

## Related pages

- [Generators]({% link _reference/generators.md %})
- [The agent contract]({% link _agents/agent-contract.md %})
