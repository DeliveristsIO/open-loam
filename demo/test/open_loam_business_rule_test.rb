require "test_helper"

# Loam::BusinessRules: the when/then engine. The condition evaluator is the
# critical SAFE boundary (data, never code); the actions are a fixed vocabulary;
# the engine fires matching rules tenant-scoped, in priority order, isolated.
class LoamBusinessRuleConditionTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-rule")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-rule")
  end

  test "each comparison op and boolean nesting evaluates correctly" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 950, status: "available")
      c = Loam::BusinessRules::Condition

      assert c.matches?({ "field" => "status", "op" => "eq", "value" => "available" }, equipment)
      assert c.matches?({ "field" => "daily_rate", "op" => "gt", "value" => 500 }, equipment)
      assert c.matches?({ "field" => "daily_rate", "op" => "lte", "value" => 950 }, equipment)
      assert c.matches?({ "field" => "status", "op" => "in", "value" => %w[available rented] }, equipment)
      assert c.matches?({ "field" => "name", "op" => "contains", "value" => "igg" }, equipment)
      assert c.matches?({ "field" => "status", "op" => "present" }, equipment)
      assert c.matches?({ "and" => [ { "field" => "status", "op" => "eq", "value" => "available" },
                                     { "not" => { "field" => "daily_rate", "op" => "lt", "value" => 100 } } ] }, equipment)
      assert c.matches?({}, equipment), "an empty condition always matches"
      refute c.matches?({ "field" => "daily_rate", "op" => "gt", "value" => 2000 }, equipment)
    end
  end

  test "a field that is not a whitelisted column is refused, never evaluated" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 950, status: "available")
      c = Loam::BusinessRules::Condition

      refute c.matches?({ "field" => "destroy", "op" => "present" }, equipment), "an arbitrary method is refused"
      refute c.matches?({ "field" => "tenant_id", "op" => "present" }, equipment), "tenant_id is refused"
      refute c.matches?({ "field" => "nonsense", "op" => "present" }, equipment)
    end
  end

  test "an encrypted column is refused in a condition (no oracle)" do
    with_tenant(@warsaw) do
      customer = Customer.create!(name: "Acme", email: "a@x.test", tax_id: "PL5260001")
      # A rule that could probe the secret bit-by-bit must never be evaluated.
      refute Loam::BusinessRules::Condition.matches?({ "field" => "tax_id", "op" => "contains", "value" => "5260" }, customer)
    end
  end

  test "conditions only ever see the record they are given, in its tenant" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 950, status: "available")
      # No way to name another tenant's data: fields resolve to THIS record only.
      assert Loam::BusinessRules::Condition.matches?({ "field" => "name", "op" => "eq", "value" => "Digger" }, equipment)
    end
  end
end

class LoamBusinessRuleActionsTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-act")
    @manager = User.create!(name: "M", email: "m@example.test", password: "password")
    with_tenant(@warsaw) { Loam::Membership.create!(user: @manager, role: "manager") }
  end

  test "notify creates a notification for the role" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 10, status: "available")
      Loam::BusinessRules::Actions.run({ "type" => "notify", "role" => "manager", "title" => "Hi" }, equipment)
      assert_equal 1, Loam::Notification.where(title: "Hi", user_id: @manager.id).count
    end
  end

  test "emit_event publishes and validates the name" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 10, status: "available")
      received = []
      subscription = Loam::Events.subscribe("test.rule.fired") { |_name, payload| received << payload }
      Loam::BusinessRules::Actions.run({ "type" => "emit_event", "name" => "test.rule.fired", "payload" => { "id" => 1 } }, equipment)
      assert_equal 1, received.size

      assert_raises(Loam::InvalidEventNameError) do
        Loam::BusinessRules::Actions.run({ "type" => "emit_event", "name" => "not a valid name" }, equipment)
      end
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription)
    end
  end

  test "set_field writes a whitelisted column but refuses the workflow status column" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 10, status: "available")
      Loam::BusinessRules::Actions.run({ "type" => "set_field", "field" => "status", "value" => "rented" }, equipment)
      assert_equal "rented", equipment.reload.status

      report = DamageReport.create!(equipment_id: equipment.id, description: "x", state: "open")
      assert_raises(ArgumentError) do
        Loam::BusinessRules::Actions.run({ "type" => "set_field", "field" => "state", "value" => "approved" }, report)
      end
      assert_equal "open", report.reload.state, "the workflow column was not written"
    end
  end
end

class LoamBusinessRuleEngineTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-eng")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-eng")
    @manager = User.create!(name: "M", email: "m@example.test", password: "password")
    with_tenant(@warsaw) { Loam::Membership.create!(user: @manager, role: "manager") }
    with_tenant(@krakow) { Loam::Membership.create!(user: @manager, role: "manager") }
  end

  test "the event subscriber fires a matching rule and logs the run" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 950, status: "available")
      Loam::BusinessRule.create!(name: "pricey", entity_type: "Equipment", trigger: "rental.equipment.pinged",
                                 condition: { "field" => "daily_rate", "op" => "gt", "value" => 500 },
                                 actions: [ { "type" => "notify", "role" => "manager", "title" => "Pricey" } ], active: true)

      Loam::Events.publish("rental.equipment.pinged", id: equipment.id)

      assert_equal 1, Loam::Notification.where(title: "Pricey").count
      run = Loam::BusinessRuleRun.last
      assert run.matched
      assert_equal [ "notify" ], run.actions_taken
    end
  end

  test "rules fire in priority order" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 950, status: "available")
      Loam::BusinessRule.create!(name: "low", entity_type: "Equipment", trigger: "rental.equipment.pinged",
                                 condition: {}, actions: [ { "type" => "notify", "role" => "manager", "title" => "B-low" } ], priority: 1, active: true)
      Loam::BusinessRule.create!(name: "high", entity_type: "Equipment", trigger: "rental.equipment.pinged",
                                 condition: {}, actions: [ { "type" => "notify", "role" => "manager", "title" => "A-high" } ], priority: 10, active: true)

      Loam::Events.publish("rental.equipment.pinged", id: equipment.id)

      assert_equal [ "A-high", "B-low" ], Loam::Notification.order(:id).pluck(:title), "higher priority ran first"
    end
  end

  test "a raising rule is isolated: it logs an error and does not break sibling rules or dispatch" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 10, status: "available")
      Loam::BusinessRule.create!(name: "boom", entity_type: "Equipment", trigger: "rental.equipment.pinged",
                                 condition: {}, actions: [ { "type" => "set_field", "field" => "no_such_field", "value" => 1 } ], priority: 10, active: true)
      Loam::BusinessRule.create!(name: "ok", entity_type: "Equipment", trigger: "rental.equipment.pinged",
                                 condition: {}, actions: [ { "type" => "notify", "role" => "manager", "title" => "Still ran" } ], priority: 1, active: true)

      assert_nothing_raised { Loam::Events.publish("rental.equipment.pinged", id: equipment.id) }

      assert_equal 1, Loam::Notification.where(title: "Still ran").count, "the sibling rule still ran"
      assert Loam::BusinessRuleRun.where(matched: false).where.not(error: nil).exists?, "the failure was logged"
    end
  end

  test "a Warsaw rule never fires on a Krakow event" do
    with_tenant(@warsaw) do
      Loam::BusinessRule.create!(name: "w-rule", entity_type: "Equipment", trigger: "rental.equipment.pinged",
                                 condition: {}, actions: [ { "type" => "notify", "role" => "manager", "title" => "W" } ], active: true)
    end
    with_tenant(@krakow) do
      equipment = Equipment.create!(name: "KrDigger", daily_rate: 10, status: "available")
      Loam::Events.publish("rental.equipment.pinged", id: equipment.id)
    end
    assert_equal 0, with_tenant(@warsaw) { Loam::Notification.where(title: "W").count }, "the Warsaw rule stayed in Warsaw"
  end

  test "a self-triggering rule terminates (depth-bounded), it does not hang" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 10, status: "available")
      Loam::BusinessRule.create!(name: "loop", entity_type: "Equipment", trigger: "rental.loop.tick",
                                 condition: {}, actions: [ { "type" => "emit_event", "name" => "rental.loop.tick", "payload" => { "id" => equipment.id } } ], active: true)

      assert_nothing_raised { Loam::Events.publish("rental.loop.tick", id: equipment.id) }
      assert_operator Loam::BusinessRuleRun.where(event_name: "rental.loop.tick").count, :<=, Loam::BusinessRules::MAX_DEPTH
    end
  end

  test "a block_transition rule vetoes a workflow transition" do
    with_tenant(@warsaw, actor: @manager) do
      Loam::BusinessRule.create!(name: "no-critical", entity_type: "DamageReport", trigger: "rental.damage_report.submit",
                                 condition: { "field" => "description", "op" => "contains", "value" => "critical" },
                                 actions: [ { "type" => "block_transition" } ], active: true)

      critical = DamageReport.create!(equipment_id: 1, description: "critical failure", state: "open")
      assert_raises(Loam::TransitionVetoedError) { critical.submit! }
      assert_equal "open", critical.reload.state, "the vetoed transition did not move"

      minor = DamageReport.create!(equipment_id: 1, description: "minor scratch", state: "open")
      minor.submit!
      assert_equal "pending_approval", minor.reload.state, "an un-vetoed report submits normally"
    end
  end
end

# Security regressions (adversarial review): a manager must not be able to point
# a rule at a GLOBAL model (e.g. User) to reach across tenants, nor set a
# credential column — a system-wide account-takeover chain.
class LoamBusinessRuleSecurityTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-br-sec")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-br-sec")
  end

  test "a rule may only target a tenant-scoped model, refused at save time" do
    with_tenant(@warsaw) do
      assert Loam::BusinessRule.new(name: "ok", trigger: "rental.x", entity_type: "Equipment").valid?
      assert Loam::BusinessRule.new(name: "event-only", trigger: "rental.x", entity_type: nil).valid?, "an event-only rule needs no entity"

      user_rule = Loam::BusinessRule.new(name: "pwn", trigger: "rental.x", entity_type: "User")
      refute user_rule.valid?, "a global model like User is refused"
      assert user_rule.errors[:entity_type].any?

      refute Loam::BusinessRule.new(name: "j1", trigger: "rental.x", entity_type: "Kernel").valid?, "a non-model class is refused"
      refute Loam::BusinessRule.new(name: "j2", trigger: "rental.x", entity_type: "NotARealModel").valid?, "an unresolvable name is refused"
    end
  end

  test "a poisoned rule targeting a global model resolves NO subject and cannot mutate a User" do
    victim = User.create!(name: "Victim", email: "victim@example.test", password: "correct-horse")
    original = victim.password_digest

    rule = with_tenant(@warsaw) do
      r = Loam::BusinessRule.create!(name: "takeover", trigger: "rental.pwn.attempt", entity_type: "Equipment",
                                     condition: {}, actions: [ { "type" => "set_field", "field" => "password_digest", "value" => "hijacked" } ], active: true)
      r.update_column(:entity_type, "User")  # bypass save-time validation to prove the RUN-time close (defense in depth)
      r
    end

    with_tenant(@warsaw) do
      assert_nil Loam::BusinessRules.send(:subject_for, rule, { id: victim.id }), "subject_for refuses a non-TenantRecord"
      assert_nothing_raised { Loam::Events.publish("rental.pwn.attempt", id: victim.id) }
    end

    assert_equal original, victim.reload.password_digest, "the victim's credential was NOT touched"
  end

  test "the emit_event -> set_field chain cannot reach a User across the depth guard" do
    victim = User.create!(name: "Victim2", email: "victim2@example.test", password: "correct-horse")
    original = victim.password_digest

    with_tenant(@warsaw) do
      # Rule A emits an event carrying the victim's id.
      Loam::BusinessRule.create!(name: "A", trigger: "rental.pwn.start", entity_type: "Equipment", condition: {},
                                 actions: [ { "type" => "emit_event", "name" => "rental.pwn.exec", "payload" => { "id" => victim.id } } ], active: true)
      # Rule B would set the victim's credential — but it targets a global model.
      b = Loam::BusinessRule.create!(name: "B", trigger: "rental.pwn.exec", entity_type: "Equipment", condition: {},
                                     actions: [ { "type" => "set_field", "field" => "password_digest", "value" => "hijacked" } ], active: true)
      b.update_column(:entity_type, "User")

      equipment = Equipment.create!(name: "Rig", daily_rate: 10, status: "available")
      assert_nothing_raised { Loam::Events.publish("rental.pwn.start", id: equipment.id) }
    end

    assert_equal original, victim.reload.password_digest, "the two-step chain never touched the victim"
  end

  test "set_field refuses a credential column even when the record really has one" do
    with_tenant(@warsaw) do
      # Customer.email is a REAL (encrypted) column — writable, but a credential a
      # rule must never touch. Before the fix, set_field would overwrite it.
      customer = Customer.create!(name: "Acme", email: "orders@acme.test", tax_id: "PL1")

      assert_raises(ArgumentError) do
        Loam::BusinessRules::Actions.run({ "type" => "set_field", "field" => "email", "value" => "attacker@evil.test" }, customer)
      end
      assert_equal "orders@acme.test", customer.reload.email, "the email column was not overwritten"

      # The name/pattern refusals also hold regardless of column existence.
      %w[password_digest encrypted_password PASSWORD some_digest].each do |field|
        assert_raises(ArgumentError, "#{field} must be refused") do
          Loam::BusinessRules::Actions.run({ "type" => "set_field", "field" => field, "value" => "x" }, customer)
        end
      end
    end
  end
end
