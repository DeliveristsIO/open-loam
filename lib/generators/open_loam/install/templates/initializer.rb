# OpenLoam configuration, tenant lifecycle hooks, and domain event subscriptions.

# Master key for field encryption at rest (OpenLoam::Encryptable). Per-tenant keys
# are derived from it via HKDF, so it must be STABLE and SECRET — never commit it.
# Set OPEN_LOAM_MASTER_KEY in the environment (or wire Rails.application.credentials)
# to a high-entropy value, e.g. `SecureRandom.hex(32)`. Only apps that actually
# `encrypts` a field need it; encryption raises a clear error if it is missing.
#
#   OpenLoam::Encryption.master_key = ENV.fetch("OPEN_LOAM_MASTER_KEY")
#
# Rotating the key without re-encrypting orphans existing ciphertext — see
# `bin/rails open_loam:encryption:rotate[Model,tenant_id]`.

# Roles every tenant of this app is expected to have. A registry read by your
# own seeding/admin code — OpenLoam does not create memberships for you, because
# who gets which role is business logic.
OpenLoam.default_roles = %w[manager employee]

# Locales that CONTENT translations (OpenLoam::Translatable) may be authored in — the
# admin's language switcher and the per-record Translations screen offer these.
# The first is the base/default; the rest overlay onto it. This is for user data
# (a product name), NOT developer UI strings — those stay Rails i18n. OpenLoam ships
# a `open_loam.*` base locale (English) for its own chrome; the admin switcher sets
# I18n.locale too, so add `config/locales/open_loam.pl.yml` (etc.) to translate the UI
# for each locale you list here.
OpenLoam.locales = %w[en]

# Observability (OpenLoam::Telemetry). By default OpenLoam wraps its async hot paths
# (scheduler tick, durable event delivery, inbound webhook ingest) in spans that
# emit ActiveSupport::Notifications events ("open_loam.span.*") — subscribe to those,
# or plug a real tracer in here:
#
#   OpenLoam::Telemetry.backend = ->(name, attributes, work) do
#     OpenTelemetry.tracer_provider.tracer("open_loam").in_span(name, attributes: attributes.transform_keys(&:to_s)) { work.call }
#   end

# Feature-string permissions (OpenLoam::Permissions) — a finer capability layer under
# the coarse role. Deny-by-default; `*` grants everything, a trailing `.*` is a
# prefix ("equipment.*"). Check with `OpenLoam.can?("equipment.edit")`,
# `require_permission!("...")` in a controller, or the `can?` view helper.
# Orthogonal to roles (OpenLoam::Membership) and field-level policies (OpenLoam::Policy).
#
#   OpenLoam::Permissions.configure do
#     role :admin,   allow: "*"
#     role :manager, allow: %w[equipment.* billing.read]
#     role :clerk,   allow: %w[equipment.read]
#   end

# Customization WITHOUT forking (OpenLoam::Overrides): disable or replace an entry in
# one of OpenLoam's keyed registries (:widgets, :broadcast_events). A stale override
# (a key that no longer exists) is warned about at boot by `check!`, so a
# typo'd override is visible instead of silently doing nothing.
#
#   OpenLoam::Overrides.disable(:widgets, "open_progress")   # drop a built-in widget
#   OpenLoam::Overrides.replace(:widgets, "audit_recent") { |actor| { kind: "count", value: 0 } }
#   OpenLoam::Overrides.disable(:broadcast_events, "open_loam.progress.")  # stop pushing it over SSE
#
# BOUNDARY: this is only for OpenLoam's in-gem registries. Override a VIEW, CONTROLLER,
# or ROUTE the standard Rails way (create a file at the same path to shadow the
# engine's, or `prepend` a module) — not here.

# Events pushed live to the browser over SSE (OpenLoam::EventStream). Default off; the
# notification pattern is enabled here so the admin bell increments without a
# reload. Add patterns (e.g. "billing.") to stream domain events to live widgets —
# nothing reaches the browser unless it matches a pattern here (security posture).
OpenLoam.broadcast_events = [ "open_loam.notification.", "open_loam.progress." ]

# Events EXCLUDED from the event log (OpenLoam::EventLog), which otherwise
# captures everything. Progress ticks are excluded because a bulk import fires
# one per row — volume without history worth keeping.
OpenLoam.uncaptured_events = [ "open_loam.progress." ]

# How long captured events are kept before the daily per-tenant prune. nil keeps
# everything, which means an unbounded table.
OpenLoam.event_log_retention = 90.days

# Response enrichers (OpenLoam::Enrichers): attach a computed block onto ANOTHER
# module's entity in admin/API responses, with no foreign-key coupling — billing
# can annotate an Equipment without Equipment knowing billing exists. Pass a
# `batch:` resolver (array -> { id => value }) so an index stays one query, not N.
#
#   OpenLoam::Enrichers.register("Equipment", key: "outstanding_balance", batch: ->(equipments) do
#     totals = Invoice.where(equipment_id: equipments.map(&:id)).group(:equipment_id).sum(:balance)
#     equipments.map(&:id).index_with { |id| totals.fetch(id, 0) }
#   end)

# Search backend (OpenLoam::Search). The default is a substring LIKE — portable and
# zero-setup. Opt into the word-level TokenDriver (also portable, no external
# service: it keeps a normalized-token index in open_loam_search_tokens) for
# order-independent, whole-word matching. `searchable_by` and every
# `Model.search(q)` call site are UNCHANGED — only this line differs; an external
# engine (Meilisearch/Elasticsearch) is a third driver behind the same seam.
# After switching, backfill existing rows once with `bin/rails open_loam:search:reindex`
# (new and updated records index themselves on save).
#
#   OpenLoam::Search.driver = OpenLoam::Search::TokenDriver

# Custom-field read-model index (OpenLoam::CustomFieldIndex). Filtering/sorting on a
# custom field is index-backed (a typed projection in open_loam_custom_field_values)
# instead of a per-row JSON scan. Records project themselves on save; backfill
# existing data once with `bin/rails open_loam:index:reindex` (or
# `OpenLoam::CustomFieldIndex.reindex(Model)`). Query with
# `OpenLoam::CustomFieldIndex.filter(Model, field_key, op, value)` — the generated
# entity index routes a `cf_field`/`cf_op`/`cf_value` filter through it.

# Single sign-on (OpenLoam::Sso). OIDC is shipped end-to-end: configure a per-tenant
# provider under /admin/sso_providers (issuer, client_id, client_secret, email
# domain, default JIT role). Home-realm discovery routes a user to their tenant's
# IdP by email domain; a verified identity is JIT-provisioned or linked to an
# existing User. The client_secret is encrypted at rest, so OPEN_LOAM_MASTER_KEY must
# be set (same key as the rest of OpenLoam::Encryptable). SAML and SCIM are documented
# seams (see docs/_foundation/overview.md). Nothing to register here for real OIDC.
#
# In tests, inject the offline fake so the flow never hits the network:
#
#   OpenLoam::Sso.builder = ->(record, redirect_uri) { OpenLoam::Sso::FakeProvider.new(record, redirect_uri: redirect_uri) }

# Roles that MUST use two-factor auth (OpenLoam::MfaCredential). At login, a user
# whose role in the chosen tenant is on this list and who has not enrolled is
# sent to set MFA up before they can work. Resolved via OpenLoam::Configs, so it can
# be a global default or a per-tenant override; empty means MFA is optional.
#
#   OpenLoam::Configs.set("security.mfa_required_roles", ["manager"], scope: :global)
#
# Auth rate-limiting / lockout (OpenLoam::AuthThrottle) guards failed password/TOTP/
# sudo attempts. Defaults: lock after 10 failures within a 15-minute window.
# Tune via OpenLoam::Configs (global or per-tenant):
#
#   OpenLoam::Configs.set("security.max_auth_attempts",   5,  scope: :global)
#   OpenLoam::Configs.set("security.auth_window_minutes", 10, scope: :global)
#
# Rack::Attack (with a cache store) is the production-scale path across multiple
# processes; the built-in DB counter is the portable single-process default.

# App-wide setting defaults (OpenLoam::Configs). A key resolves override → global
# row → this declared default, so declaring one here needs no migration and no
# row — a tenant reads the default until someone overrides it in the admin
# Settings screen (/admin/configs). Values keep their type (bool/number/string/
# hash), and a per-tenant override never leaks to another tenant.
#
#   OpenLoam.config_defaults = { "billing.currency" => "USD", "billing.net_terms" => 30 }
#
# To change the company-wide baseline at runtime (not per tenant), write a
# global row: `OpenLoam::Configs.set("billing.currency", "EUR", scope: :global)`.

# Feature flags (OpenLoam::Features). Declare known capabilities and their default
# state; a flag with no row resolves to its declared default, and managers flip
# a tenant's override at /admin/features. A flag gates a CAPABILITY (is this on
# for the tenant), orthogonal to roles/policies, which gate a PERSON.
#
#   OpenLoam.feature_defaults = {
#     "beta_dashboard" => { default: false, description: "New dashboard, rolled out per tenant." }
#   }
#
# In a controller: `require_feature!(:beta_dashboard)` (404s when off); in a
# view: `<%% if feature_on?(:beta_dashboard) %>`. Flip app-wide with
# `OpenLoam::Features.enable(:beta_dashboard, scope: :global)`.

# What a brand-new tenant gets for free. Registered at file scope on purpose:
# inside `to_prepare` this would re-register on every code reload.
OpenLoam.on_tenant_created do |tenant|
  # Seed roles/defaults for a new tenant here. MUST be idempotent —
  # `bin/rails open_loam:sync` re-runs these for every existing tenant, which is how
  # a default added in a later release reaches tenants that already exist.
  # Use find_or_create_by!, never create!. The block runs inside
  # OpenLoam.as_tenant(tenant), so tenant-scoped writes need no extra ceremony.
  #
  # Baseline managed lookup lists (OpenLoam::Dictionary) — a FieldDefinition of type
  # "dictionary" can then point a custom field at the key, rendering a select:
  #
  #   severity = OpenLoam::Dictionary.find_or_create_by!(key: "damage_severity") { |d| d.name = "Damage severity" }
  #   [%w[minor Minor], %w[major Major], %w[critical Critical]].each_with_index do |(value, label), i|
  #     severity.entries.find_or_create_by!(value: value) { |e| e.label = label; e.position = i }
  #   end

  # Materialize the registered tenant-scope schedules (see OpenLoam::Scheduler.register
  # below) as rows for this tenant. A no-op until you register one.
  OpenLoam::Scheduler.sync_tenant(tenant)
end

# Recurring jobs (OpenLoam::Scheduler). Register default schedules here at file scope;
# on_tenant_created materializes the tenant-scope ones per tenant. A "tenant" job
# is enqueued with `tenant_id:` (establish it with OpenLoam.as_tenant); a "system" job
# runs once with no tenant. job_class MUST be a real ActiveJob (validated — never
# arbitrary code). Wire the runner to system cron, every minute:
#
#   * * * * * cd /path/to/app && bin/rails open_loam:scheduler:tick
#
# The claim is atomic, so running it from several hosts never double-fires a job.
#
#   OpenLoam::Scheduler.register(key: "nightly_digest", name: "Nightly digest",
#                            job_class: "DigestJob", schedule: "0 7 * * *", scope: "tenant")
#
# Only ALLOWLISTED job classes are schedulable (a registered one, or one listed
# here) — so a tenant admin can't schedule ActiveStorage::PurgeJob or a mailer:
#
#   OpenLoam.schedulable_jobs = %w[DigestJob ReindexJob]

# Domain event subscriptions. Subscribe to a single event or a whole domain
# (trailing dot = prefix). Register them here at file scope, not inside
# `to_prepare`: subscriptions are global, so a reload would add a second copy
# of each one and every event would be handled twice.
#
#   OpenLoam::Events.subscribe("billing.subscription.renewed") do |name, payload|
#     BillingMailer.renewal_receipt(payload[:id]).deliver_later
#   end
#
#   OpenLoam::Events.subscribe("rental.") do |name, payload|
#     Rails.logger.info("[open_loam event] #{name} #{payload.inspect}")
#   end
#
# Event -> in-app notification is the intended pattern for telling someone
# something. The subscriber runs in the publisher's tenant context, so the
# notification lands in the right tenant with no extra ceremony:
#
#   OpenLoam::Events.subscribe("rental.damage_report.approve") do |_name, payload|
#     OpenLoam::Notifications.notify_role(:manager, title: "Damage report approved")
#   end

# Business rules (OpenLoam::BusinessRule) are the admin-editable cousin of the
# subscriptions above: a manager declares, per tenant, WHEN a condition holds on
# a triggering record THEN run a fixed vocabulary of safe actions (notify,
# emit_event, set_field, block_transition). The condition is DATA — a
# whitelisted {field, op, value} tree, never evaluated as code — so a tenant
# admin can wire up automation without a deploy and without a code-injection
# surface. The engine subscribes itself at boot; nothing to register here.
# Manage rules under /admin/business_rules and see why they fired in the run log.
