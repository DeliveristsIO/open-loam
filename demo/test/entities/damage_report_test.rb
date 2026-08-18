require "test_helper"

# Generated guardrail tests for DamageReport. They prove the Loam
# invariants hold for THIS entity: tenant isolation, loud failure without
# context, audit-by-default, lifecycle events, membership-gated policies.
# Extend freely; never delete.
class DamageReportLoamTest < ActiveSupport::TestCase
  setup do
    @tenant_a = Loam::Tenant.create!(name: "Tenant A", slug: "a-damage_report")
    @tenant_b = Loam::Tenant.create!(name: "Tenant B", slug: "b-damage_report")
    @manager = User.create!(name: "Manager")
    @employee = User.create!(name: "Employee")

    with_tenant(@tenant_a) do
      Loam::Membership.create!(user: @manager, role: "manager")
      Loam::Membership.create!(user: @employee, role: "employee")
    end
  end

  test "guardrail: records are invisible outside their tenant" do
    record_id = with_tenant(@tenant_a) { DamageReport.create!(equipment_id: 1, description: "Sample description 0", approved: true).id }

    with_tenant(@tenant_a) { assert_equal 1, DamageReport.count }

    with_tenant(@tenant_b) do
      assert_equal 0, DamageReport.count
      assert_raises(ActiveRecord::RecordNotFound) { DamageReport.find(record_id) }
    end
  end

  test "guardrail: touching the model with no tenant context raises" do
    assert_raises(Loam::MissingTenantError) { DamageReport.count }
    assert_raises(Loam::MissingTenantError) { DamageReport.new }
  end

  test "guardrail: a record cannot be written into a foreign tenant" do
    record = with_tenant(@tenant_a) { DamageReport.create!(equipment_id: 1, description: "Sample description 0", approved: true) }

    with_tenant(@tenant_b) do
      assert_raises(Loam::MissingTenantError) { record.update!(equipment_id: 2, description: "Sample description 1", approved: false) }
    end
  end

  test "every change is audited with actor and changeset" do
    with_tenant(@tenant_a, actor: @manager) do
      record = DamageReport.create!(equipment_id: 1, description: "Sample description 0", approved: true)

      audit = Loam::AuditRecord.find_by(
        auditable_type: "DamageReport", auditable_id: record.id, action: "create"
      )
      assert audit, "expected an audit record for the create"
      assert_equal @manager.id, audit.actor_id
      assert_includes audit.changeset.keys, "equipment_id"
    end
  end

  test "lifecycle events are published with the tenant stamped" do
    received = []
    subscription = Loam::Events.subscribe("rental.damage_report.created") do |_name, payload|
      received << payload
    end

    with_tenant(@tenant_a, actor: @manager) { DamageReport.create!(equipment_id: 1, description: "Sample description 0", approved: true) }

    assert_equal 1, received.size
    assert_equal @tenant_a.id, received.first[:tenant_id]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  test "approving a report publishes billing.penalty.due" do
    received = []
    subscription = Loam::Events.subscribe("billing.penalty.due") do |_name, payload|
      received << payload
    end

    with_tenant(@tenant_a, actor: @manager) do
      report = DamageReport.create!(equipment_id: 1, description: "Cracked casing", approved: false)
      report.update!(approved: true)

      assert_equal 1, received.size
      assert_equal report.id, received.first[:id]
    end
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  test "policy: only members of the current tenant may act" do
    record = with_tenant(@tenant_a) { DamageReport.create!(equipment_id: 1, description: "Sample description 0", approved: true) }

    with_tenant(@tenant_a) do
      assert DamageReportPolicy.new(@manager, record).update?

      outsider = User.create!(name: "Outsider")
      outsider_policy = DamageReportPolicy.new(outsider, record)
      refute outsider_policy.update?
      refute outsider_policy.writable?(:equipment_id)
    end
  end
end
