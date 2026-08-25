---
title: Getting Started
description: A hands-on walkthrough from an empty Rails app to a working multi-tenant, permissioned, audited feature.
nav_order: 1
---

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

echo 'gem "open-loam", github: "DeliveristsIO/open-loam"' >> Gemfile
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

anna  = User.create!(name: "Anna",  email: "anna@example.com",  password: "password123")
tomek = User.create!(name: "Tomek", email: "tomek@example.com", password: "password123")

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
measured; see the [benchmark](https://github.com/DeliveristsIO/open-loam/blob/main/ai/golden_tasks.md), where agents completed 10
such tasks with zero isolation violations, versus 1-in-10 on plain Rails.)

---

## 7. Going further — the rest of the foundation

The five sections above cover the everyday loop. Loam ships more, each the same
shape: one obvious way, safe by default. A tour of the real API:

**Soft-delete — a recycle bin, not an erase.** Every generated entity gets it.
`record.soft_delete!` hides the row from every query by default (still
tenant-scoped); `Model.with_deleted` / `only_deleted` see the bin;
`record.restore!` brings it back. The soft-delete is audited. Hard `destroy`
still erases for a deliberate "forget me".

**Settings — per-tenant configuration.** `Loam::Configs.get("billing.currency",
default: "PLN")` resolves most-specific-first: this tenant's override → the
global row → a declared default. `Loam::Configs.set(key, value)` writes the
current tenant's override; a manager-only **Settings** admin screen edits them.

**Feature flags — a per-tenant kill-switch.** `Loam::Features.on?(:beta_dashboard)`
gates a *capability* (is this on for the tenant), orthogonal to policy which
gates a *person*. `require_feature!(:x)` in a controller 404s when off;
`feature_on?(:x)` hides UI. Flip per tenant from the **Features** screen.

**Encryption at rest — for regulated data.** `encrypts :tax_id` in a model
transparently seals the column with a per-tenant AES-256-GCM key (a DB dump
leaks nothing; tenant A's key never decrypts tenant B's row). `encrypts :email,
searchable: true` adds a keyed blind index so exact-match lookup still works.
Set a `LOAM_MASTER_KEY`; plaintext never reaches the audit trail, events, or
webhooks.

**MFA + step-up — a second factor.** Users enroll a TOTP authenticator; login
prompts for a code when active; recovery codes are single-use. `require_sudo!`
gates a sensitive action behind a fresh re-challenge (an MFA user re-proves with
a code, never a password downgrade). Require MFA per role via a config key.

**AI mutation approval gate — human-in-the-loop.** When an agent runs under
confirm-mode, a write is *staged* instead of applied: `Loam::PendingActions.stage(
summary:, on:, action:, changes:)` records the intent with a before/after
preview and touches nothing; a manager reviews the queue and `approve!(by:)`
executes it in a transaction, audited to the approver. The proposal is encrypted
at rest and never leaks in the preview. This is the primitive the MCP server
(roadmap) will use to keep agent writes reviewable.

**And more, the same shape** — each guardrail-tested and one-lined in `AGENTS.md`:

- **Undo / history** — every record's `/admin/history` reverts a change with one
  click; the undo is itself recorded, so undoing an `undo` is redo (encrypted
  fields and workflow state are never reverted — state undoes via the reverse
  transition).
- **Inbound webhooks** — a public `/webhooks/:token` receiver, HMAC-verified over
  the raw body and replay-safe, that republishes the verified event onto the bus.
- **Durable event subscribers** — `Loam::DurableEvents.register(...)` persists each
  delivery and retries it (at-least-once, dead-letter, redelivery sweep) — the
  reliable twin of the inline `Loam::Events.subscribe`.
- **Feature-string permissions** — `Loam.can?("equipment.edit")` with wildcard
  grants (`equipment.*`) per role, deny-by-default, under the coarse role.
- **Generated-screen i18n** — `translates :name` localizes record *data*; the
  admin language switcher also translates the generated admin layout, entity
  screens, and flashes through the `loam.*` locale namespace. Loam's built-in
  screens (such as scheduler and webhooks) remain English for now.
- **Scheduler, dictionaries, saved views, real-time SSE, bulk CSV import/export,
  auto-OpenAPI, an observability seam** — the full list is the pillar table in the
  [README](https://github.com/DeliveristsIO/open-loam/blob/main/README.md), and the visual
  [architecture map](https://claude.ai/code/artifact/949311d3-5e14-4f07-a8ad-7b1bb5bd87ad)
  shows how they connect.

Each of these has its own guardrail-tested conventions in `AGENTS.md`, so an
agent extends them the same way it extends anything else.

---

## Where to look next

- [`AGENTS.md`](https://github.com/DeliveristsIO/open-loam/blob/main/lib/generators/loam/install/templates/AGENTS.md) — the full
  contract, and the best one-page description of "the one way to do each thing".
- [**Architecture map**](https://claude.ai/code/artifact/949311d3-5e14-4f07-a8ad-7b1bb5bd87ad) — a visual tour of the modules and how they connect.
- [How Loam works]({% link _foundation/overview.md %}) — how each pillar is built and why.
- [Roadmap](https://github.com/DeliveristsIO/open-loam/blob/main/ROADMAP.md) — what's shipped and what's deliberately deferred.
- [`demo/`](https://github.com/DeliveristsIO/open-loam/tree/main/demo) — a complete version of the app sketched above, with tests.
- [Contributing](https://github.com/DeliveristsIO/open-loam/blob/main/CONTRIBUTING.md) — if you want to extend Loam itself.
