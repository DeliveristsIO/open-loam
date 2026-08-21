# Loam configuration, tenant lifecycle hooks, and domain event subscriptions.

# Master key for field encryption at rest (Loam::Encryptable). Per-tenant keys
# are derived from it via HKDF, so it must be STABLE and SECRET — never commit it.
# Set LOAM_MASTER_KEY in the environment (or wire Rails.application.credentials)
# to a high-entropy value, e.g. `SecureRandom.hex(32)`. Only apps that actually
# `encrypts` a field need it; encryption raises a clear error if it is missing.
#
#   Loam::Encryption.master_key = ENV.fetch("LOAM_MASTER_KEY")
#
# Rotating the key without re-encrypting orphans existing ciphertext — see
# `bin/rails loam:encryption:rotate[Model,tenant_id]`.

# Roles every tenant of this app is expected to have. A registry read by your
# own seeding/admin code — Loam does not create memberships for you, because
# who gets which role is business logic.
Loam.default_roles = %w[manager employee]

# Locales that CONTENT translations (Loam::Translatable) may be authored in — the
# admin's language switcher and the per-record Translations screen offer these.
# The first is the base/default; the rest overlay onto it. This is for user data
# (a product name), NOT developer UI strings — those stay Rails i18n.
Loam.locales = %w[en]

# Customization WITHOUT forking (Loam::Overrides): disable or replace an entry in
# one of Loam's keyed registries (:widgets, :broadcast_events). A stale override
# (a key that no longer exists) is warned about at boot by `check!`, so a
# typo'd override is visible instead of silently doing nothing.
#
#   Loam::Overrides.disable(:widgets, "open_progress")   # drop a built-in widget
#   Loam::Overrides.replace(:widgets, "audit_recent") { |actor| { kind: "count", value: 0 } }
#   Loam::Overrides.disable(:broadcast_events, "loam.progress.")  # stop pushing it over SSE
#
# BOUNDARY: this is only for Loam's in-gem registries. Override a VIEW, CONTROLLER,
# or ROUTE the standard Rails way (create a file at the same path to shadow the
# engine's, or `prepend` a module) — not here.

# Events pushed live to the browser over SSE (Loam::EventStream). Default off; the
# notification pattern is enabled here so the admin bell increments without a
# reload. Add patterns (e.g. "billing.") to stream domain events to live widgets —
# nothing reaches the browser unless it matches a pattern here (security posture).
Loam.broadcast_events = [ "loam.notification.", "loam.progress." ]

# Response enrichers (Loam::Enrichers): attach a computed block onto ANOTHER
# module's entity in admin/API responses, with no foreign-key coupling — billing
# can annotate an Equipment without Equipment knowing billing exists. Pass a
# `batch:` resolver (array -> { id => value }) so an index stays one query, not N.
#
#   Loam::Enrichers.register("Equipment", key: "outstanding_balance", batch: ->(equipments) do
#     totals = Invoice.where(equipment_id: equipments.map(&:id)).group(:equipment_id).sum(:balance)
#     equipments.map(&:id).index_with { |id| totals.fetch(id, 0) }
#   end)

# Search backend (Loam::Search). The default is a substring LIKE — portable and
# zero-setup. Opt into the word-level TokenDriver (also portable, no external
# service: it keeps a normalized-token index in loam_search_tokens) for
# order-independent, whole-word matching. `searchable_by` and every
# `Model.search(q)` call site are UNCHANGED — only this line differs; an external
# engine (Meilisearch/Elasticsearch) is a third driver behind the same seam.
# After switching, backfill existing rows once with `bin/rails loam:search:reindex`
# (new and updated records index themselves on save).
#
#   Loam::Search.driver = Loam::Search::TokenDriver

# Single sign-on (Loam::Sso). OIDC is shipped end-to-end: configure a per-tenant
# provider under /admin/sso_providers (issuer, client_id, client_secret, email
# domain, default JIT role). Home-realm discovery routes a user to their tenant's
# IdP by email domain; a verified identity is JIT-provisioned or linked to an
# existing User. The client_secret is encrypted at rest, so LOAM_MASTER_KEY must
# be set (same key as the rest of Loam::Encryptable). SAML and SCIM are documented
# seams (see docs/architecture.md). Nothing to register here for real OIDC.
#
# In tests, inject the offline fake so the flow never hits the network:
#
#   Loam::Sso.builder = ->(record, redirect_uri) { Loam::Sso::FakeProvider.new(record, redirect_uri: redirect_uri) }

# Roles that MUST use two-factor auth (Loam::MfaCredential). At login, a user
# whose role in the chosen tenant is on this list and who has not enrolled is
# sent to set MFA up before they can work. Resolved via Loam::Configs, so it can
# be a global default or a per-tenant override; empty means MFA is optional.
#
#   Loam::Configs.set("security.mfa_required_roles", ["manager"], scope: :global)

# App-wide setting defaults (Loam::Configs). A key resolves override → global
# row → this declared default, so declaring one here needs no migration and no
# row — a tenant reads the default until someone overrides it in the admin
# Settings screen (/admin/configs). Values keep their type (bool/number/string/
# hash), and a per-tenant override never leaks to another tenant.
#
#   Loam.config_defaults = { "billing.currency" => "USD", "billing.net_terms" => 30 }
#
# To change the company-wide baseline at runtime (not per tenant), write a
# global row: `Loam::Configs.set("billing.currency", "EUR", scope: :global)`.

# Feature flags (Loam::Features). Declare known capabilities and their default
# state; a flag with no row resolves to its declared default, and managers flip
# a tenant's override at /admin/features. A flag gates a CAPABILITY (is this on
# for the tenant), orthogonal to roles/policies, which gate a PERSON.
#
#   Loam.feature_defaults = {
#     "beta_dashboard" => { default: false, description: "New dashboard, rolled out per tenant." }
#   }
#
# In a controller: `require_feature!(:beta_dashboard)` (404s when off); in a
# view: `<%% if feature_on?(:beta_dashboard) %>`. Flip app-wide with
# `Loam::Features.enable(:beta_dashboard, scope: :global)`.

# What a brand-new tenant gets for free. Registered at file scope on purpose:
# inside `to_prepare` this would re-register on every code reload.
Loam.on_tenant_created do |tenant|
  # Seed roles/defaults for a new tenant here. MUST be idempotent —
  # `bin/rails loam:sync` re-runs these for every existing tenant, which is how
  # a default added in a later release reaches tenants that already exist.
  # Use find_or_create_by!, never create!. The block runs inside
  # Loam.as_tenant(tenant), so tenant-scoped writes need no extra ceremony.
  #
  # Baseline managed lookup lists (Loam::Dictionary) — a FieldDefinition of type
  # "dictionary" can then point a custom field at the key, rendering a select:
  #
  #   severity = Loam::Dictionary.find_or_create_by!(key: "damage_severity") { |d| d.name = "Damage severity" }
  #   [%w[minor Minor], %w[major Major], %w[critical Critical]].each_with_index do |(value, label), i|
  #     severity.entries.find_or_create_by!(value: value) { |e| e.label = label; e.position = i }
  #   end

  # Materialize the registered tenant-scope schedules (see Loam::Scheduler.register
  # below) as rows for this tenant. A no-op until you register one.
  Loam::Scheduler.sync_tenant(tenant)
end

# Recurring jobs (Loam::Scheduler). Register default schedules here at file scope;
# on_tenant_created materializes the tenant-scope ones per tenant. A "tenant" job
# is enqueued with `tenant_id:` (establish it with Loam.as_tenant); a "system" job
# runs once with no tenant. job_class MUST be a real ActiveJob (validated — never
# arbitrary code). Wire the runner to system cron, every minute:
#
#   * * * * * cd /path/to/app && bin/rails loam:scheduler:tick
#
# The claim is atomic, so running it from several hosts never double-fires a job.
#
#   Loam::Scheduler.register(key: "nightly_digest", name: "Nightly digest",
#                            job_class: "DigestJob", schedule: "0 7 * * *", scope: "tenant")
#
# Only ALLOWLISTED job classes are schedulable (a registered one, or one listed
# here) — so a tenant admin can't schedule ActiveStorage::PurgeJob or a mailer:
#
#   Loam.schedulable_jobs = %w[DigestJob ReindexJob]

# Domain event subscriptions. Subscribe to a single event or a whole domain
# (trailing dot = prefix). Register them here at file scope, not inside
# `to_prepare`: subscriptions are global, so a reload would add a second copy
# of each one and every event would be handled twice.
#
#   Loam::Events.subscribe("billing.subscription.renewed") do |name, payload|
#     BillingMailer.renewal_receipt(payload[:id]).deliver_later
#   end
#
#   Loam::Events.subscribe("rental.") do |name, payload|
#     Rails.logger.info("[loam event] #{name} #{payload.inspect}")
#   end
#
# Event -> in-app notification is the intended pattern for telling someone
# something. The subscriber runs in the publisher's tenant context, so the
# notification lands in the right tenant with no extra ceremony:
#
#   Loam::Events.subscribe("rental.damage_report.approve") do |_name, payload|
#     Loam::Notifications.notify_role(:manager, title: "Damage report approved")
#   end

# Business rules (Loam::BusinessRule) are the admin-editable cousin of the
# subscriptions above: a manager declares, per tenant, WHEN a condition holds on
# a triggering record THEN run a fixed vocabulary of safe actions (notify,
# emit_event, set_field, block_transition). The condition is DATA — a
# whitelisted {field, op, value} tree, never evaluated as code — so a tenant
# admin can wire up automation without a deploy and without a code-injection
# surface. The engine subscribes itself at boot; nothing to register here.
# Manage rules under /admin/business_rules and see why they fired in the run log.
