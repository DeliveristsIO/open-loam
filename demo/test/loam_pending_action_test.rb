require "test_helper"

# Loam::PendingActions: staging an agent's write for human approval. Nothing is
# mutated until a manager approves; approval is a role-gated workflow transition;
# the proposal never leaks (encrypted at rest, redacted in preview and audit).
class LoamPendingActionTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-pa")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-pa")
    @manager = User.create!(name: "Manager", email: "mgr@example.test", password: "password")
    @employee = User.create!(name: "Employee", email: "emp@example.test", password: "password")

    with_tenant(@warsaw) do
      Loam::Membership.create!(user: @manager, role: "manager")
      Loam::Membership.create!(user: @employee, role: "employee")
    end
  end

  test "staging records the intent without mutating the target" do
    with_tenant(@warsaw, actor: @employee) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 950, status: "available")

      pending = Loam::PendingActions.stage(
        summary: "Raise rate", on: equipment, action: :update, changes: { daily_rate: 1100 }
      )

      assert_equal "pending", pending.status
      assert_equal @employee.id, pending.actor_id
      assert_equal 950, Equipment.find(equipment.id).daily_rate, "the target must be untouched until approval"
    end
  end

  test "preview shows the before/after of each proposed field" do
    with_tenant(@warsaw, actor: @employee) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 950, status: "available")
      pending = Loam::PendingActions.stage(
        summary: "Raise rate", on: equipment, action: :update, changes: { daily_rate: 1100 }
      )

      assert_equal({ "from" => 950, "to" => 1100 }, pending.preview["daily_rate"].transform_values(&:to_i))
    end
  end

  test "a manager approves and the change is applied; an employee is refused" do
    id = with_tenant(@warsaw, actor: @employee) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 950, status: "available")
      Loam::PendingActions.stage(summary: "Raise", on: equipment, action: :update, changes: { daily_rate: 1100 }).id
    end

    with_tenant(@warsaw) do
      pending = Loam::PendingAction.find(id)

      assert_raises(Loam::NotAuthorizedError) { pending.approve!(by: @employee) }
      assert_equal "pending", pending.reload.status, "a refused approval changes nothing"

      pending.approve!(by: @manager)
      assert_equal "executed", pending.reload.status
      assert_equal @manager.id, pending.reviewed_by_id
      assert_equal 1100, Equipment.find(pending.target_id).daily_rate
    end
  end

  test "the applied change is audited as the approving manager's, not the proposer's" do
    id = with_tenant(@warsaw, actor: @employee) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 950, status: "available")
      Loam::PendingActions.stage(summary: "Raise", on: equipment, action: :update, changes: { daily_rate: 1100 }).id
    end

    with_tenant(@warsaw) do
      pending = Loam::PendingAction.find(id)
      pending.approve!(by: @manager)

      audit = Loam::AuditRecord.where(auditable_type: "Equipment", auditable_id: pending.target_id, action: "update").last
      assert_equal @manager.id, audit.actor_id, "the human who approved owns the change"
    end
  end

  test "reject never executes" do
    id = with_tenant(@warsaw, actor: @employee) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 950, status: "available")
      Loam::PendingActions.stage(summary: "Raise", on: equipment, action: :update, changes: { daily_rate: 1100 }).id
    end

    with_tenant(@warsaw) do
      pending = Loam::PendingAction.find(id)
      pending.reject!(by: @manager, reason: "too steep")

      assert_equal "rejected", pending.reload.status
      assert_match "too steep", pending.result
      assert_equal 950, Equipment.find(pending.target_id).daily_rate, "a rejected change is never applied"
    end
  end

  test "an identical proposal collapses to one row via the idempotency key" do
    with_tenant(@warsaw, actor: @employee) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 950, status: "available")

      first = Loam::PendingActions.stage(summary: "Raise", on: equipment, action: :update, changes: { daily_rate: 1100 })
      again = Loam::PendingActions.stage(summary: "Raise", on: equipment, action: :update, changes: { daily_rate: 1100 })

      assert_equal first.id, again.id
      assert_equal 1, Loam::PendingAction.count
    end
  end

  test "a failed execution rolls back: status failed, target unchanged" do
    id = with_tenant(@warsaw, actor: @employee) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 950, status: "available")
      Loam::PendingActions.stage(summary: "Bad", on: equipment, action: :update, changes: { nonexistent_field: "x" }).id
    end

    with_tenant(@warsaw) do
      pending = Loam::PendingAction.find(id)
      pending.approve!(by: @manager)

      assert_equal "failed", pending.reload.status
      assert pending.error.present?
      assert_equal 950, Equipment.find(pending.target_id).daily_rate, "no partial write on failure"
    end
  end

  test "a pending action is invisible and unaffectable from another tenant" do
    id = with_tenant(@warsaw, actor: @employee) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 950, status: "available")
      Loam::PendingActions.stage(summary: "Raise", on: equipment, action: :update, changes: { daily_rate: 1100 }).id
    end

    with_tenant(@krakow) do
      assert_equal 0, Loam::PendingAction.count
      assert_nil Loam::PendingAction.find_by(id: id)
    end
  end

  # The full leak closure: an encrypted target field never appears in plaintext —
  # not in the preview, not in the stored changeset column, not in the audit.
  test "a staged change to an encrypted field leaks the value nowhere" do
    id = with_tenant(@warsaw, actor: @manager) do
      customer = Customer.create!(name: "Acme", email: "a@acme.test", tax_id: "PL-OLD")
      Loam::PendingActions.stage(
        summary: "Update tax id", on: customer, action: :update, changes: { tax_id: "PL-SECRET-999" }
      ).id
    end

    with_tenant(@warsaw) do
      pending = Loam::PendingAction.find(id)

      assert_equal({ "from" => "[encrypted]", "to" => "[encrypted]" }, pending.preview["tax_id"])

      raw = Loam::PendingAction.connection.select_value("SELECT changeset FROM loam_pending_actions WHERE id = #{id}")
      assert raw.start_with?("v1:")
      refute_includes raw, "PL-SECRET-999", "no plaintext in the stored changeset"

      audit = Loam::AuditRecord.where(auditable_type: "Loam::PendingAction", auditable_id: id).first
      assert_equal "[encrypted]", audit.changeset["changeset"]
      refute_includes audit.changeset.to_json, "PL-SECRET-999", "no plaintext in the audit trail"
    end
  end
end

# The admin approval queue end to end.
class AdminPendingActionsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-pa-flow")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    @tomek = User.create!(name: "Tomek", email: "tomek@example.test", password: "password")

    with_tenant(@tenant) do
      Loam::Membership.create!(user: @anna, role: "manager")
      Loam::Membership.create!(user: @tomek, role: "employee")
      @equipment = Equipment.create!(name: "Digger", daily_rate: 950, status: "available")
      @pending = Loam::PendingActions.stage(
        summary: "Raise rate", on: @equipment, action: :update, changes: { daily_rate: 1100 }, actor: @tomek
      )
    end
  end

  test "a manager approves in the queue and the change is applied" do
    post admin_session_path, params: { email: "anna@example.test", password: "password" }

    get admin_pending_actions_path
    assert_response :success
    assert_match "Raise rate", response.body

    post approve_admin_pending_action_path(@pending)
    assert_response :redirect

    with_tenant(@tenant) do
      assert_equal "executed", @pending.reload.status
      assert_equal 1100, Equipment.find(@equipment.id).daily_rate
    end
  end

  test "an employee cannot reach the approval queue" do
    post admin_session_path, params: { email: "tomek@example.test", password: "password" }

    get admin_pending_actions_path
    assert_response :forbidden

    post approve_admin_pending_action_path(@pending)
    assert_response :forbidden
  end
end
