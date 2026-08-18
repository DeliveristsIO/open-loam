# Demo data: an equipment-rental company with two branches (tenants).
# Log into /admin as different user+tenant combos to see isolation and roles.

warsaw = Loam::Tenant.find_or_create_by!(slug: "warsaw") { |t| t.name = "Branch Warsaw" }
krakow = Loam::Tenant.find_or_create_by!(slug: "krakow") { |t| t.name = "Branch Krakow" }

anna = User.find_or_create_by!(name: "Anna (manager)")
tomek = User.find_or_create_by!(name: "Tomek (employee)")

Loam.as_tenant(warsaw, actor: anna) do
  Loam::Membership.find_or_create_by!(user: anna) { |m| m.role = "manager" }
  Loam::Membership.find_or_create_by!(user: tomek) { |m| m.role = "employee" }

  Equipment.find_or_create_by!(name: "Excavator CAT 320") { |e| e.daily_rate = 950.0; e.status = "available" }
  Equipment.find_or_create_by!(name: "Concrete mixer") { |e| e.daily_rate = 120.0; e.status = "rented" }
end

Loam.as_tenant(krakow, actor: anna) do
  Loam::Membership.find_or_create_by!(user: anna) { |m| m.role = "manager" }

  Equipment.find_or_create_by!(name: "Scaffolding set") { |e| e.daily_rate = 80.0; e.status = "available" }
end

puts "Seeded: 2 tenants, 2 users, 3 equipment records."
