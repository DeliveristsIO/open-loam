# Loam configuration, tenant lifecycle hooks, and domain event subscriptions.

# Roles every branch of this rental company has. A registry read by seeding and
# admin code — Loam does not create memberships for you, because who gets which
# role is business logic.
Loam.default_roles = %w[manager employee]

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
