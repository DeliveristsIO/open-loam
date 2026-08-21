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

# Events pushed live to the browser over SSE (Loam::EventStream). Default off; the
# notification pattern is enabled here so the admin bell increments without a
# reload. Add patterns (e.g. "billing.") to stream domain events to live widgets —
# nothing reaches the browser unless it matches a pattern here (security posture).
Loam.broadcast_events = [ "loam.notification." ]

# Response enrichers (Loam::Enrichers): attach a computed block onto ANOTHER
# module's entity in admin/API responses, with no foreign-key coupling — billing
# can annotate an Equipment without Equipment knowing billing exists. Pass a
# `batch:` resolver (array -> { id => value }) so an index stays one query, not N.
#
#   Loam::Enrichers.register("Equipment", key: "outstanding_balance", batch: ->(equipments) do
#     totals = Invoice.where(equipment_id: equipments.map(&:id)).group(:equipment_id).sum(:balance)
#     equipments.map(&:id).index_with { |id| totals.fetch(id, 0) }
#   end)

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
end

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
