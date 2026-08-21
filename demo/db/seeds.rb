# Demo data: an equipment-rental company with two branches (tenants).
# Log into /admin as different users to see isolation and roles. Anna is a
# manager in both branches, so she gets the tenant picker; Tomek belongs to
# Warsaw only and lands straight on the dashboard.

DEMO_PASSWORD = "password123".freeze

# Idempotent: the password is only written for a new user (or one left without
# a digest by the migration that introduced passwords), never overwriting one
# somebody changed.
def seed_user(name, email)
  user = User.find_or_initialize_by(name: name)
  user.email = email
  user.password = DEMO_PASSWORD if user.password_digest.blank?
  user.save!
  user
end

warsaw = Loam::Tenant.find_or_create_by!(slug: "warsaw") { |t| t.name = "Branch Warsaw" }
krakow = Loam::Tenant.find_or_create_by!(slug: "krakow") { |t| t.name = "Branch Krakow" }

# Per-tenant defaults (the asset_tag field definition) come from the
# Loam.on_tenant_created hook in config/initializers/loam.rb, which fires only
# on creation. Syncing backfills tenants that already existed — the same thing
# `bin/rails loam:sync` does after a deploy that adds a new default.
Loam.sync_tenants!

# Settings (Loam::Configs). The declared default for the late fee is 25 (see
# config/initializers/loam.rb); this global row raises the company-wide baseline
# to 30, and Warsaw overrides it again below — so the Settings screen shows all
# three levels: declared default, global, per-tenant override.
Loam::Configs.set("rental.late_fee_per_day", 30, scope: :global)

# Sign in at /admin with either address and the password below.
anna = seed_user("Anna (manager)", "anna@example.com")
tomek = seed_user("Tomek (employee)", "tomek@example.com")

# Memberships stay in seeds rather than moving into the on_tenant_created hook:
# they need users, which are host-app data a tenant hook knows nothing about.
Loam.as_tenant(warsaw, actor: anna) do
  Loam::Membership.find_or_create_by!(user: anna) { |m| m.role = "manager" }
  Loam::Membership.find_or_create_by!(user: tomek) { |m| m.role = "employee" }

  # Warsaw charges a higher late fee than the company baseline.
  Loam::Configs.set("rental.late_fee_per_day", 45)

  # Warsaw is in the beta_dashboard rollout; Krakow is not, so its "Beta" nav
  # link stays hidden and /admin/dashboard/beta 404s there.
  Loam::Features.enable(:beta_dashboard)

  # Migration-free fields: added from the admin, not a generator.
  Loam::FieldDefinition.find_or_create_by!(entity_type: "Equipment", name: "serial_number") do |fd|
    fd.field_type = "string"
  end
  Loam::FieldDefinition.find_or_create_by!(entity_type: "Equipment", name: "warranty_expires_at") do |fd|
    fd.field_type = "date"
    fd.writable_roles = [ "manager" ]
  end

  excavator = Equipment.find_or_create_by!(name: "Excavator CAT 320") { |e| e.daily_rate = 950.0; e.status = "available" }
  excavator.set_custom_field(:serial_number, "SN-CAT320-001")
  excavator.set_custom_field(:warranty_expires_at, Date.new(2027, 6, 30))
  excavator.save!

  Equipment.find_or_create_by!(name: "Concrete mixer") { |e| e.daily_rate = 120.0; e.status = "rented" }

  # A customer with encrypted PII at rest (Loam::Encryptable). email is
  # searchable via its blind index, so find_by_email keeps this idempotent —
  # a plain find_or_create_by on the encrypted column could never match, since
  # each encryption uses a fresh IV. The tax_id is encrypted but not searchable.
  Customer.find_by_email("orders@acme.example") ||
    Customer.create!(name: "Acme Construction", email: "orders@acme.example", tax_id: "PL5260001246")

  # Saved views of the Equipment list (Loam::Perspectives): a tenant-wide default
  # that shows only available gear, and a private view Anna sorts by price.
  Loam::Perspective.find_or_create_by!(entity_type: "Equipment", name: "Available only", visibility: "tenant") do |p|
    p.is_default = true
    p.config = { "filters" => { "status" => "available" }, "sort" => { "field" => "name", "dir" => "asc" } }
  end
  Loam::Perspective.find_or_create_by!(entity_type: "Equipment", name: "Anna's priciest", owner_id: anna.id, visibility: "private") do |p|
    p.config = { "sort" => { "field" => "daily_rate", "dir" => "desc" } }
  end

  # A business rule (Loam::BusinessRules): WHEN a damage report is submitted AND
  # its description mentions "urgent", notify the branch managers. Declared as
  # DATA (trigger + safe condition + typed action), fired by the event engine.
  Loam::BusinessRule.find_or_create_by!(name: "Flag urgent damage reports") do |rule|
    rule.entity_type = "DamageReport"
    rule.trigger = "rental.damage_report.submit"
    rule.condition = { "field" => "description", "op" => "contains", "value" => "urgent" }
    rule.actions = [ { "type" => "notify", "role" => "manager", "title" => "Urgent damage report submitted" } ]
    rule.active = true
  end

  # An AI-proposed price change waiting in the approval queue (Loam::PendingActions):
  # staged, not applied, until a manager approves it under Approvals. Idempotent —
  # the idempotency key collapses a re-seed to the same row.
  Loam::PendingActions.stage(
    summary: "Raise the concrete mixer's daily rate to 150",
    on: Equipment.find_by(name: "Concrete mixer"),
    action: :update,
    changes: { daily_rate: 150 }
  )
end

Loam.as_tenant(krakow, actor: anna) do
  Loam::Membership.find_or_create_by!(user: anna) { |m| m.role = "manager" }

  Equipment.find_or_create_by!(name: "Scaffolding set") { |e| e.daily_rate = 80.0; e.status = "available" }
end

puts "Seeded: 2 tenants, 2 users, 3 equipment records, rental settings (global + Warsaw override), beta_dashboard on for Warsaw, 1 customer with encrypted PII, 1 pending approval, 2 saved views, 1 business rule."
