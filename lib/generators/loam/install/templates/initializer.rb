# Loam configuration, tenant lifecycle hooks, and domain event subscriptions.

# Roles every tenant of this app is expected to have. A registry read by your
# own seeding/admin code — Loam does not create memberships for you, because
# who gets which role is business logic.
Loam.default_roles = %w[manager employee]

# What a brand-new tenant gets for free. Registered at file scope on purpose:
# inside `to_prepare` this would re-register on every code reload.
Loam.on_tenant_created do |tenant|
  # Seed roles/defaults for a new tenant here. MUST be idempotent —
  # `bin/rails loam:sync` re-runs these for every existing tenant, which is how
  # a default added in a later release reaches tenants that already exist.
  # Use find_or_create_by!, never create!. The block runs inside
  # Loam.as_tenant(tenant), so tenant-scoped writes need no extra ceremony.
end

# Subscribe to a single event or a whole domain (trailing dot = prefix):
#
#   Loam::Events.subscribe("billing.subscription.renewed") do |name, payload|
#     BillingMailer.renewal_receipt(payload[:id]).deliver_later
#   end
#
#   Loam::Events.subscribe("rental.") do |name, payload|
#     Rails.logger.info("[loam event] #{name} #{payload.inspect}")
#   end
Rails.application.config.to_prepare do
end
