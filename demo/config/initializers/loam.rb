# Loam configuration, tenant lifecycle hooks, and domain event subscriptions.

# Master key for field encryption at rest (Loam::Encryptable). Per-tenant keys
# are derived from this via HKDF, so it must be stable and secret.
#
# !!! DEV/TEST ONLY !!! This literal fallback is committed on purpose so the demo
# runs out of the box. A REAL deployment MUST set LOAM_MASTER_KEY (or wire
# Rails.application.credentials) to a high-entropy secret — `SecureRandom.hex(32)` —
# and NEVER commit it. Rotating this key without re-encrypting orphans existing data.
Loam::Encryption.master_key = ENV.fetch("LOAM_MASTER_KEY", "loam-demo-dev-master-key-not-for-production-use-2f8c1a")

# Roles every branch of this rental company has. A registry read by seeding and
# admin code — Loam does not create memberships for you, because who gets which
# role is business logic.
Loam.default_roles = %w[manager employee]

# Events pushed live to the browser over SSE (Loam::EventStream). Default off;
# here the notification pattern is on, so the bell increments without a reload.
# Add more patterns (e.g. "rental.") to stream domain events to live widgets.
Loam.broadcast_events = [ "loam.notification.", "loam.progress." ]

# Response enricher (Loam::Enrichers): billing/rental cross-cutting concerns can
# attach a computed block onto another entity's response WITHOUT that entity
# knowing about them. Here: how many damage reports are awaiting approval for a
# piece of equipment — Equipment knows nothing about DamageReport; the enricher
# joins them at read time. Uses the BATCH path so an index is one query, not N.
Loam::Enrichers.register("Equipment", key: "open_damage_reports", batch: ->(equipments) do
  counts = DamageReport.where(equipment_id: equipments.map(&:id), state: "pending_approval").group(:equipment_id).count
  equipments.map(&:id).index_with { |id| counts.fetch(id, 0) }
end)

# Search backend (Loam::Search). The default is a substring LIKE; the demo opts
# into the portable word-level TokenDriver so search is order-independent
# ("excavator cat" finds "CAT 320 Excavator"). `searchable_by` and every
# `Model.search(q)` call site are unchanged — only this line differs. Existing
# records need `Loam::Search.reindex(Model)` once (seeds do it; in production run
# `bin/rails loam:search:reindex`); new/updated records index themselves on save.
Loam::Search.driver = Loam::Search::TokenDriver

# Recurring jobs (Loam::Scheduler). Modules self-register default schedules at
# file scope; on_tenant_created (below) materializes the tenant-scope ones as
# rows per tenant. A cron entry runs `bin/rails loam:scheduler:tick` every minute.
# Here: touch every equipment nightly at 03:00 (a stand-in for real periodic work).
Loam::Scheduler.register(key: "nightly_touch", name: "Nightly equipment touch",
                         job_class: "DemoScheduledJob", schedule: "0 3 * * *", scope: "tenant")

# SSO (Loam::Sso). The demo has no real identity provider and MUST NOT hit the
# network, so it injects the offline FakeProvider for every SSO round-trip: its
# authorization_url loops straight back to our callback and it returns verified
# claims for the email typed at the sign-in box. A real deployment deletes this
# line and configures a genuine OIDC issuer + client_secret on the SSO screen.
# (Demo/test only — the FakeProvider is never for production.)
Loam::Sso.builder = ->(record, redirect_uri) { Loam::Sso::FakeProvider.new(record, redirect_uri: redirect_uri) }

# Roles that MUST use two-factor auth (Loam::MfaCredential). At login, a user
# whose role in the chosen branch is on this list and who has not enrolled is
# sent to set MFA up first. Resolved via Loam::Configs, so it can be global or a
# per-branch override; left empty here so the demo logs in without MFA.
#
#   Loam::Configs.set("security.mfa_required_roles", ["manager"], scope: :global)

# App-wide setting defaults (Loam::Configs). A key resolves override → global
# row → this declared default, so declaring one here needs no migration and no
# row — a branch reads the default until someone overrides it in the Settings
# screen. The currency is the same everywhere; the late fee is just the baseline.
Loam.config_defaults = {
  "rental.currency" => "PLN",
  "rental.late_fee_per_day" => 25
}

# Feature flags (Loam::Features): capabilities toggled per tenant for rollout or
# as a kill-switch, independent of who is signed in. A flag with no row resolves
# to the declared default here; managers flip a tenant's override at
# /admin/features. Distinct from roles/policies, which gate a PERSON, not a
# capability.
Loam.feature_defaults = {
  "beta_dashboard" => { default: false, description: "A branch-manager preview dashboard, rolled out branch by branch." },
  "damage_reports.require_photo" => { default: false, description: "Require a photo attachment before a damage report can be filed." }
}

# What a brand-new branch (tenant) gets for free. Registered at file scope on
# purpose: inside `to_prepare` this would re-register on every code reload.
Loam.on_tenant_created do |tenant|
  # Every branch tracks an asset tag on its equipment, managers only. This is a
  # migration-free field (Loam::FieldDefinition), so a new branch is usable the
  # moment it exists — no seed script, no deploy.
  #
  # MUST be idempotent — `bin/rails loam:sync` re-runs this for every existing
  # branch, which is how a default added today reaches branches created last
  # year. find_or_create_by!, never create!. The block runs inside
  # Loam.as_tenant(tenant), so the write needs no extra ceremony.
  Loam::FieldDefinition.find_or_create_by!(entity_type: "Equipment", name: "asset_tag") do |fd|
    fd.field_type = "string"
    fd.writable_roles = [ "manager" ]
  end

  # Materialize the registered tenant-scope schedules as rows for this tenant
  # (idempotent — also re-run for existing tenants by `bin/rails loam:sync`).
  Loam::Scheduler.sync_tenant(tenant)
end

# Domain event subscriptions. Subscribe to a single event or a whole domain
# (trailing dot = prefix). Registered here at file scope, not inside
# `to_prepare`: subscriptions are global, so a reload would add a second copy
# of each one and every event would be handled twice.
#
#   Loam::Events.subscribe("rental.") do |name, payload|
#     Rails.logger.info("[loam event] #{name} #{payload.inspect}")
#   end

# Event -> in-app notification: when a manager approves a damage report, the
# branch's managers find it in their bell at /admin/notifications. The
# subscriber runs in the publisher's tenant context, so `notify_role` resolves
# managers of THAT branch and the notifications land in that tenant.
Loam::Events.subscribe("rental.damage_report.approve") do |_name, payload|
  Loam::Notifications.notify_role(
    :manager,
    title: "Damage report ##{payload[:id]} approved",
    body: "Moved from #{payload[:from]} to #{payload[:to]}. A penalty charge may follow.",
    source: DamageReport.find_by(id: payload[:id])
  )
end
