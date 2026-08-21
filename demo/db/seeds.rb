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

  # An SSO provider (Loam::SsoProvider): anyone with a warsaw-corp.example email
  # is sent to the branch's identity provider (OIDC) and provisioned as an
  # employee on first login. The demo injects an offline FakeProvider (see the
  # initializer), so signing in with e.g. nowak@warsaw-corp.example JIT-creates
  # the user in Warsaw — no network, no password. The client_secret is encrypted.
  Loam::SsoProvider.find_or_create_by!(domain: "warsaw-corp.example") do |p|
    p.name = "Warsaw Corp SSO"
    p.protocol = "oidc"
    p.issuer = "https://idp.warsaw-corp.example"
    p.client_id = "loam-demo"
    p.client_secret = "demo-secret-not-real"
    p.jit_role = "employee"
    p.active = true
  end

  # A managed lookup list (Loam::Dictionary): damage severity, curated in the
  # admin without a deploy. The DamageReport "severity" custom field below is a
  # dictionary-typed field driven by it, so its edit form renders a select of
  # these entries and stores the chosen value.
  severity = Loam::Dictionary.find_or_create_by!(key: "damage_severity") { |d| d.name = "Damage severity" }
  [
    { value: "minor",    label: "Minor",    color: "#2e7d32", position: 1 },
    { value: "major",    label: "Major",    color: "#f9a825", position: 2 },
    { value: "critical", label: "Critical", color: "#c62828", position: 3, is_default: true }
  ].each { |attrs| severity.entries.find_or_create_by!(value: attrs[:value]) { |e| e.assign_attributes(attrs) } }

  Loam::FieldDefinition.find_or_create_by!(entity_type: "DamageReport", name: "severity") do |fd|
    fd.field_type = "dictionary"
    fd.dictionary_key = "damage_severity"
  end

  # A finished long-running task (Loam::ProgressJob) so the Tasks screen shows
  # history; run a live one from that screen's "Run a demo job" button.
  Loam::ProgressJob.find_or_create_by!(name: "Nightly reindex") do |job|
    job.total = 42
    job.completed = 42
    job.status = "completed"
    job.started_at = 1.hour.ago
    job.finished_at = 55.minutes.ago
  end

  # The demo uses the TokenDriver (see config/initializers/loam.rb). New records
  # index themselves on save, but a RE-seed touches existing rows with
  # find_or_create_by! (no save, no tokens), so rebuild the index explicitly —
  # the same thing `bin/rails loam:search:reindex` does after a deploy.
  [ Equipment, Customer, DamageReport ].each { |model| Loam::Search.reindex(model) }
end

Loam.as_tenant(krakow, actor: anna) do
  Loam::Membership.find_or_create_by!(user: anna) { |m| m.role = "manager" }

  Equipment.find_or_create_by!(name: "Scaffolding set") { |e| e.daily_rate = 80.0; e.status = "available" }

  # Krakow gets the same managed severity list (each tenant curates its own).
  severity = Loam::Dictionary.find_or_create_by!(key: "damage_severity") { |d| d.name = "Damage severity" }
  [
    { value: "minor",    label: "Minor",    color: "#2e7d32", position: 1 },
    { value: "critical", label: "Critical", color: "#c62828", position: 2, is_default: true }
  ].each { |attrs| severity.entries.find_or_create_by!(value: attrs[:value]) { |e| e.assign_attributes(attrs) } }

  Loam::Search.reindex(Equipment)
end

puts "Seeded: 2 tenants, 2 users, 3 equipment records, rental settings (global + Warsaw override), beta_dashboard on for Warsaw, 1 customer with encrypted PII, 1 pending approval, 2 saved views, 1 business rule, 1 SSO provider (Warsaw, OIDC), a damage_severity dictionary per tenant (+ a dictionary-typed DamageReport field), 1 completed task, word-level search index (TokenDriver)."
