require "test_helper"

# L-704: undo/redo built on the audit trail. Undoing a change applies its inverse
# and records ITSELF as an audit, so redo = undoing the undo. Guardrails: only the
# latest field change is undoable (no silent clobber of newer edits); encrypted
# fields and the workflow column are never reverted here.
class LoamUndoTest < ActiveSupport::TestCase
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch", slug: "warsaw-undo")
    @other = Loam::Tenant.create!(name: "Other", slug: "other-undo")
    @anna = User.create!(name: "Anna", email: "anna-undo@example.test", password: "password")
  end

  def latest_update_audit(record)
    Loam::AuditRecord.where(auditable_type: record.class.name, auditable_id: record.id, action: %w[update undo]).order(:id).last
  end

  test "undoing an update reverts the field and records the undo as its own audit" do
    with_tenant(@tenant, actor: @anna) do
      eq = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")
      eq.update!(name: "Excavator")

      Loam::Undo.undo(latest_update_audit(eq))

      assert_equal "Digger", eq.reload.name
      assert_equal "undo", latest_update_audit(eq).action, "the undo is itself an audit"
    end
  end

  test "redo = undo the undo, re-applying the change" do
    with_tenant(@tenant, actor: @anna) do
      eq = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")
      eq.update!(name: "Excavator")

      Loam::Undo.undo(latest_update_audit(eq))     # back to Digger, writes an "undo" audit
      assert_equal "Digger", eq.reload.name

      Loam::Undo.undo(latest_update_audit(eq))     # undo the undo = redo
      assert_equal "Excavator", eq.reload.name
    end
  end

  test "an older change can't be undone while a newer one exists (no silent clobber)" do
    with_tenant(@tenant, actor: @anna) do
      eq = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")
      eq.update!(name: "Excavator")
      first_update = latest_update_audit(eq)
      eq.update!(daily_rate: 250)

      error = assert_raises(Loam::Undo::NotUndoableError) { Loam::Undo.undo(first_update) }
      assert_match "newer change", error.message
      assert_equal 250, eq.reload.daily_rate, "the newer change is untouched"
    end
  end

  test "encrypted fields are skipped — there is no old value to restore" do
    with_tenant(@tenant, actor: @anna) do
      eq = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")
      # Simulate an audit whose changeset mixes a normal field and a redacted one.
      audit = Loam::AuditRecord.create!(auditable_type: "Equipment", auditable_id: eq.id,
                                        action: "update", actor_id: @anna.id,
                                        changeset: { "name" => [ "Digger", "Excavator" ], "status" => "[encrypted]" })
      eq.update_column(:name, "Excavator")

      Loam::Undo.undo(audit)
      assert_equal "Digger", eq.reload.name  # name reverted; the "[encrypted]" entry ignored, no error
    end
  end

  test "an audit that only touched encrypted fields has nothing to revert" do
    with_tenant(@tenant, actor: @anna) do
      eq = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")
      audit = Loam::AuditRecord.create!(auditable_type: "Equipment", auditable_id: eq.id,
                                        action: "update", actor_id: @anna.id,
                                        changeset: { "status" => "[encrypted]" })
      assert_raises(Loam::Undo::NotUndoableError) { Loam::Undo.undo(audit) }
    end
  end

  test "the workflow column is never reverted by a direct write" do
    with_tenant(@tenant, actor: @anna) do
      report = DamageReport.create!(description: "Cracked boom")
      report.submit!  # a legit transition: open -> submitted, writes a "state" change audit
      transition_audit = latest_update_audit(report)

      # Undoing it must not try to write `state` directly (the transition gate
      # would raise); with only `state` in the changeset there's nothing else.
      assert_raises(Loam::Undo::NotUndoableError) { Loam::Undo.undo(transition_audit) }
      assert_equal "pending_approval", report.reload.state, "state unchanged — undo via the reverse transition instead"
    end
  end

  test "undoing a create soft-deletes; undoing that (restore) brings it back" do
    with_tenant(@tenant, actor: @anna) do
      eq = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")
      create_audit = Loam::AuditRecord.where(auditable_type: "Equipment", auditable_id: eq.id, action: "create").first

      Loam::Undo.undo(create_audit)
      assert eq.reload.deleted?, "undo of a create soft-deletes"

      soft_delete_audit = Loam::AuditRecord.where(auditable_type: "Equipment", auditable_id: eq.id, action: "soft_delete").last
      Loam::Undo.undo(soft_delete_audit)
      refute eq.reload.deleted?, "undo of the soft-delete restores"
    end
  end

  test "a policy withholds fields the role may not write" do
    with_tenant(@tenant, actor: @anna) do
      eq = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")
      eq.update!(daily_rate: 250)
      audit = latest_update_audit(eq)

      # A policy that forbids writing daily_rate → the revert skips it → nothing left.
      policy = Struct.new(:ok) do
        def writable?(field) = field.to_s != "daily_rate"
      end.new(true)
      assert_raises(Loam::Undo::NotUndoableError) { Loam::Undo.undo(audit, policy: policy) }
      assert_equal 250, eq.reload.daily_rate
    end
  end

  test "an audit from another tenant is refused" do
    other_audit = with_tenant(@other, actor: @anna) do
      Loam::Membership.create!(user: @anna, role: "manager")
      eq = Equipment.create!(name: "Foreign", daily_rate: 10, status: "available")
      eq.update!(name: "Changed")
      latest_update_audit(eq)
    end

    with_tenant(@tenant, actor: @anna) do
      assert_raises(Loam::Undo::NotUndoableError) { Loam::Undo.undo(other_audit) }
    end
  end
end

class LoamHistoryScreenTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch", slug: "warsaw-hist")
    @anna = User.create!(name: "Anna", email: "anna-hist@example.test", password: "password")
    with_tenant(@tenant) { Loam::Membership.create!(user: @anna, role: "manager") }
    @eq = with_tenant(@tenant, actor: @anna) do
      e = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")
      e.update!(name: "Excavator")
      e
    end
    post admin_session_path, params: { email: "anna-hist@example.test", password: "password" }
    post select_tenant_admin_session_path, params: { tenant_id: @tenant.id }
  end

  test "the history screen lists changes and the undo button reverts one" do
    get admin_history_path(type: "Equipment", record_id: @eq.id)
    assert_response :success
    assert_match "Excavator", response.body

    audit = with_tenant(@tenant) { Loam::AuditRecord.where(auditable_type: "Equipment", auditable_id: @eq.id, action: "update").order(:id).last }
    post admin_undo_history_path(id: audit.id, type: "Equipment", record_id: @eq.id)
    assert_response :redirect
    assert_equal "Digger", with_tenant(@tenant) { @eq.reload.name }
  end

  test "history for a record in another tenant is not reachable" do
    other = Loam::Tenant.create!(name: "Other", slug: "other-hist")
    foreign = with_tenant(other, actor: @anna) { Equipment.create!(name: "Foreign", daily_rate: 5, status: "available") }
    get admin_history_path(type: "Equipment", record_id: foreign.id)
    assert_response :not_found
  end
end
