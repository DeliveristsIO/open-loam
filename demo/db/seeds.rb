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
end

Loam.as_tenant(krakow, actor: anna) do
  Loam::Membership.find_or_create_by!(user: anna) { |m| m.role = "manager" }

  Equipment.find_or_create_by!(name: "Scaffolding set") { |e| e.daily_rate = 80.0; e.status = "available" }
end

puts "Seeded: 2 tenants, 2 users, 3 equipment records, rental settings (global + Warsaw override)."
