require "test_helper"

# Loam::Workflow on a real entity: DamageReport moves
# open -> pending_approval -> approved/rejected, and only a manager decides.
class LoamWorkflowTest < ActiveSupport::TestCase
  setup do
    @tenant = Loam::Tenant.create!(name: "Tenant A", slug: "a-workflow")
    @manager = User.create!(name: "Manager")
    @employee = User.create!(name: "Employee")

    with_tenant(@tenant) do
      Loam::Membership.create!(user: @manager, role: "manager")
      Loam::Membership.create!(user: @employee, role: "employee")
    end
  end

  test "a new record starts in the initial state" do
    with_tenant(@tenant, actor: @employee) do
      report = DamageReport.create!(equipment_id: 1, description: "Cracked casing")

      assert_equal "open", report.state
      assert report.open?
    end
  end

  test "a legal transition moves the record and publishes from/to" do
    received = []
    subscription = Loam::Events.subscribe("rental.damage_report.submit") { |_name, payload| received << payload }

    with_tenant(@tenant, actor: @employee) do
      report = DamageReport.create!(equipment_id: 1, description: "Cracked casing")
      report.submit!

      assert_equal "pending_approval", report.reload.state
      assert_equal 1, received.size
      assert_equal({ id: report.id, from: "open", to: "pending_approval" },
                   received.first.slice(:id, :from, :to))
      assert_equal @tenant.id, received.first[:tenant_id]
    end
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  test "a transition that does not start from the current state raises" do
    with_tenant(@tenant, actor: @manager) do
      report = DamageReport.create!(equipment_id: 1, description: "Cracked casing")

      assert_raises(Loam::InvalidTransitionError) { report.approve! }
      assert_equal "open", report.reload.state, "the illegal transition must not have written anything"
    end
  end

  test "a role-gated transition is refused for the wrong role and allowed for the right one" do
    report_id = with_tenant(@tenant, actor: @employee) do
      report = DamageReport.create!(equipment_id: 1, description: "Cracked casing")
      report.submit!
      report.id
    end

    with_tenant(@tenant, actor: @employee) do
      report = DamageReport.find(report_id)
      assert_raises(Loam::NotAuthorizedError) { report.approve! }
      assert_equal "pending_approval", report.reload.state
    end

    with_tenant(@tenant, actor: @manager) do
      report = DamageReport.find(report_id)
      report.approve!
      assert_equal "approved", report.reload.state
    end
  end

  test "a role-gated transition with no actor at all raises" do
    with_tenant(@tenant, actor: @employee) do
      report = DamageReport.create!(equipment_id: 1, description: "Cracked casing")
      report.submit!
    end

    report = with_tenant(@tenant) { DamageReport.first }
    with_tenant(@tenant) { assert_raises(Loam::NotAuthorizedError) { report.reject! } }
  end

  test "the workflow column only accepts declared states" do
    with_tenant(@tenant, actor: @manager) do
      report = DamageReport.new(equipment_id: 1, description: "Cracked casing", state: "sent_to_space")

      refute report.valid?
      assert_match(/is not one of: open, pending_approval, approved, rejected/, report.errors[:state].join)
    end
  end

  test "workflow_transitions_available reflects state and role" do
    with_tenant(@tenant, actor: @employee) do
      report = DamageReport.create!(equipment_id: 1, description: "Cracked casing")
      assert_equal [ :submit ], report.workflow_transitions_available

      report.submit!
      assert_empty report.workflow_transitions_available, "an employee may not approve or reject"
    end

    report = with_tenant(@tenant) { DamageReport.first }
    with_tenant(@tenant, actor: @manager) do
      assert_equal [ :approve, :reject ], report.workflow_transitions_available
    end

    # No actor: role-gated moves are filtered out rather than raising, so an
    # admin screen can always ask what to render.
    with_tenant(@tenant) { assert_empty report.workflow_transitions_available }
  end

  test "a state predicate never shadows a column of the same name" do
    with_tenant(@tenant, actor: @manager) do
      report = DamageReport.create!(equipment_id: 1, description: "Cracked casing", approved: false)
      report.submit!
      report.approve!

      assert_equal "approved", report.state
      refute report.approved?, "approved? must still read the boolean column, not the workflow state"
      assert report.rejected? == false
      refute report.open?
    end
  end

  test "the definition is frozen and introspectable" do
    definition = DamageReport.loam_workflow

    assert definition.frozen?
    assert_equal "state", definition.column
    assert_equal "open", definition.initial
    assert_equal %w[open pending_approval approved rejected], definition.states

    approve = definition.transitions[:approve]
    assert_equal [ "pending_approval" ], approve.from
    assert_equal "approved", approve.to
    assert_equal [ :manager ], approve.roles
  end

  test "a transition is audited like any other change, with no extra audit record" do
    with_tenant(@tenant, actor: @manager) do
      report = DamageReport.create!(equipment_id: 1, description: "Cracked casing")
      report.submit!

      audits = Loam::AuditRecord.where(auditable_type: "DamageReport", auditable_id: report.id, action: "update")
      assert_equal 1, audits.count
      assert_equal [ "open", "pending_approval" ], audits.first.changeset["state"]
    end
  end
end
