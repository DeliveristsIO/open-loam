# Demo data: an equipment-rental company with two branches (tenants).
# Log into /admin as different user+tenant combos to see isolation and roles.

warsaw = Loam::Tenant.find_or_create_by!(slug: "warsaw") { |t| t.name = "Branch Warsaw" }
krakow = Loam::Tenant.find_or_create_by!(slug: "krakow") { |t| t.name = "Branch Krakow" }

# Per-tenant defaults (the asset_tag field definition) come from the
# Loam.on_tenant_created hook in config/initializers/loam.rb, which fires only
# on creation. Syncing backfills tenants that already existed — the same thing
# `bin/rails loam:sync` does after a deploy that adds a new default.
Loam.sync_tenants!

anna = User.find_or_create_by!(name: "Anna (manager)")
tomek = User.find_or_create_by!(name: "Tomek (employee)")

# Memberships stay in seeds rather than moving into the on_tenant_created hook:
# they need users, which are host-app data a tenant hook knows nothing about.
Loam.as_tenant(warsaw, actor: anna) do
  Loam::Membership.find_or_create_by!(user: anna) { |m| m.role = "manager" }
  Loam::Membership.find_or_create_by!(user: tomek) { |m| m.role = "employee" }

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

puts "Seeded: 2 tenants, 2 users, 3 equipment records."
