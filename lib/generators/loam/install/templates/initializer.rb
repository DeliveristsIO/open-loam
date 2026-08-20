# Loam configuration, tenant lifecycle hooks, and domain event subscriptions.

# Roles every tenant of this app is expected to have. A registry read by your
# own seeding/admin code — Loam does not create memberships for you, because
# who gets which role is business logic.
Loam.default_roles = %w[manager employee]

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
