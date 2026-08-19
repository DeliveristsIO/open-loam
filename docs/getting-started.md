# Getting started with Loam

This is a hands-on walkthrough: from an empty Rails app to a working
multi-tenant, permissioned, audited feature — with the real commands and the
real code each step produces. If the pitch didn't land, this should: you'll
*see* what Loam decides for you, and what's left for you to write.

We'll build a slice of an **equipment-rental** system: a company with several
branch offices (each sees only its own gear), managers who can change prices,
and a damage-report approval flow. That's a real business app — tenancy,
roles, workflow, audit — and by the end you'll have written almost none of the
plumbing.

---

## 1. Install

Loam is a Rails engine gem. Start from a stock Rails 8 app (SQLite is fine):

```bash
rails new rentals
cd rentals

echo 'gem "open-loam", github: "DeliveristsIO/loam"' >> Gemfile
bundle install

bin/rails g loam:install
bin/rails db:migrate
```

> **On the name.** The product is **Loam**; the gem is distributed as
> **`open-loam`** (the plain `loam` name is an unrelated 2016 placeholder on
> RubyGems). Install from GitHub as shown while Loam is pre-1.0. The Ruby module
> stays `Loam::` and the generators stay `loam:install` / `loam:entity` — only
> the gem's distribution name is `open-loam`.

`loam:install` is the moment the "80%" arrives. It generates:

```
db/migrate/…                users, tenants, memberships, audit records,
                            field definitions, notifications, api tokens, webhooks
app/models/user.rb          a minimal password-auth User
config/initializers/loam.rb tenant lifecycle hooks + event subscriptions
app/controllers/admin/…     a working admin console (login, dashboard, notifications)
AGENTS.md                   the contract an AI agent (or teammate) follows
test/loam_guardrails_test.rb structural tests that fail if you break tenancy
```

**You now have** — before writing a single line of your own — login, the
notion of a tenant (branch office) and a user's role within it, an audit
trail, an admin shell, and tests that enforce tenant isolation. That's the
6-weeks-of-plumbing you didn't do.

---

## 2. Your first entity

One generator creates a whole tenant-scoped, audited feature:

```bash
bin/rails g loam:entity Equipment name:string daily_rate:decimal status:string --domain rental
bin/rails db:migrate
```

This writes the model, an admin CRUD screen, a policy, a JSON API controller,
and its own isolation tests. The model is four lines and every important word
is a promise kept by inheritance:

```ruby
class Equipment < Loam::TenantRecord   # ← tenant-scoped: queries auto-filter by branch
  include Loam::Auditable              # ← every change recorded (who/what/when/branch)
  include Loam::Eventful               # ← create/update/destroy emit domain events
  include Loam::CustomFields           # ← admins can add fields with no migration
  include Loam::Commentable            # ← comments on the record
  include Loam::Attachable             # ← file attachments
  include Loam::Searchable

  event_domain :rental
  searchable_by :name, :status
end
```

That's the whole model the generator writes — every capability arrives by
inheritance. You didn't write a `where(tenant_id: …)` anywhere. You can't forget
it either: a query with no tenant in context **raises** rather than leaking
across branches, and a guardrail test fails if any business model skips
`Loam::TenantRecord`.

---

## 3. See it work

Create two branches and two users, then sign in. In `bin/rails console`:

```ruby
warsaw = Loam::Tenant.create!(name: "Warsaw", slug: "warsaw")
krakow = Loam::Tenant.create!(name: "Krakow", slug: "krakow")

anna  = User.create!(name: "Anna",  email: "anna@example.com",  password: "secret123")
tomek = User.create!(name: "Tomek", email: "tomek@example.com", password: "secret123")

# roles are per branch — Anna manages Warsaw, Tomek works there
Loam.as_tenant(warsaw) do
  Loam::Membership.create!(user: anna,  role: "manager")
  Loam::Membership.create!(user: tomek, role: "employee")
  Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
end

Loam.as_tenant(krakow) do
  Loam::Membership.create!(user: anna, role: "manager")
  Equipment.create!(name: "Scaffolding", daily_rate: 80, status: "available")
end
```

Now the isolation is real, not decorative:

```ruby
Loam.as_tenant(warsaw) { Equipment.pluck(:name) }   # => ["Excavator"]
Loam.as_tenant(krakow) { Equipment.pluck(:name) }   # => ["Scaffolding"]
Equipment.count                                      # => raises Loam::MissingTenantError
```

Start the app — `bin/rails server` → `http://localhost:3000/admin` — sign in as
Anna. Because she belongs to two branches she gets a branch picker; Tomek would
land straight in Warsaw. Switch branches and the equipment list changes with
you.

---

## 4. A permission rule — one line

Anyone at a branch can manage equipment, but only a manager should change the
price. That's a single declaration in the generated policy
(`app/policies/equipment_policy.rb`):

```ruby
class EquipmentPolicy < Loam::Policy
  field :daily_rate, writable: [:manager]   # employees see it, can't edit it
  def destroy? = role == :manager
end
```

The admin form and the controller's permit-list both obey it — an employee
can't change the price through the UI *or* by hand-crafting the request. No
per-controller `params.permit` juggling.

---

## 5. A real feature: an approval workflow

Now the part every business app needs and no framework hands you: a process.
Add a damage report that a manager approves, which fires an event that becomes
a notification. Generate the entity, then give the model a workflow:

```bash
bin/rails g loam:entity DamageReport equipment_id:integer description:text state:string --domain rental
bin/rails db:migrate
```

The generator writes the model with the usual concerns; you add one line —
`include Loam::Workflow` (it's opt-in) — and the workflow block:

```ruby
class DamageReport < Loam::TenantRecord
  include Loam::Auditable
  include Loam::Eventful
  include Loam::CustomFields
  include Loam::Commentable
  include Loam::Attachable
  include Loam::Searchable
  include Loam::Workflow        # ← you add this line

  event_domain :rental
  searchable_by :description, :state

  workflow :state, initial: "open" do
    state "open"; state "pending_approval"; state "approved"; state "rejected"

    transition :submit,  from: "open",             to: "pending_approval"
    transition :approve, from: "pending_approval", to: "approved", roles: [:manager]
    transition :reject,  from: "pending_approval", to: "rejected", roles: [:manager]
  end
end
```

That gives you `report.submit!`, `report.approve!`, `report.reject!` — each one
checks the current state is legal, checks the actor's role (`approve!` refuses a
non-manager with `Loam::NotAuthorizedError`), records the change in the audit
trail, and publishes `rental.damage_report.approve`. Turn that event into a
notification for the branch's managers, in `config/initializers/loam.rb`:

```ruby
Loam::Events.subscribe("rental.damage_report.approve") do |_name, payload|
  Loam::Notifications.notify_role(
    :manager,
    title: "Damage report ##{payload[:id]} approved",
    body:  "Moved from #{payload[:from]} to #{payload[:to]}.",
    source: DamageReport.find_by(id: payload[:id])
  )
end
```

Because the subscriber runs inside the event's tenant context,
`notify_role(:manager, …)` reaches exactly the managers of *that* branch — you
never write a branch filter. The notification shows up in the admin's bell.

**Count what you built here and what you didn't.** You wrote a workflow
declaration, a policy line, and a subscriber. You did *not* build: tenancy,
roles, the audit trail, the event bus, the notification model, or the admin
screens. That's the trade Loam makes.

---

## 6. The AI-agent angle

Everything above has one obvious way to do it, written down in `AGENTS.md`. So
you can hand the next feature to an AI agent (Claude Code, Codex, …) as a plain
business sentence:

> "Add a `Supplier` entity with a name and a rating; tenant-scoped; only
> managers can edit the rating; emit `purchasing.supplier.created`."

The agent reads `AGENTS.md`, runs the same `loam:entity` generator, adds the
policy line and the event — and **can't** silently produce a cross-tenant leak,
because the guardrail tests fail if it tries. You review a small, conventional
diff instead of auditing bespoke security code. (This isn't a promise — it's
measured; see the [benchmark](../ai/golden_tasks.md), where agents completed 10
such tasks with zero isolation violations, versus 1-in-10 on plain Rails.)

---

## Where to look next

- [`AGENTS.md`](../lib/generators/loam/install/templates/AGENTS.md) — the full
  contract, and the best one-page description of "the one way to do each thing".
- [Architecture](architecture.md) — how each pillar is built and why.
- [`demo/`](../demo) — a complete version of the app sketched above, with tests.
- [Contributing](../CONTRIBUTING.md) — if you want to extend Loam itself.
