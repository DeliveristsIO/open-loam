require "test_helper"

# Generated guardrail tests for Equipment. They prove the Loam
# invariants hold for THIS entity: tenant isolation, loud failure without
# context, audit-by-default, lifecycle events, membership-gated policies.
# Extend freely; never delete.
class EquipmentLoamTest < ActiveSupport::TestCase
  setup do
    @tenant_a = Loam::Tenant.create!(name: "Tenant A", slug: "a-equipment")
    @tenant_b = Loam::Tenant.create!(name: "Tenant B", slug: "b-equipment")
    @manager = User.create!(name: "Manager")
    @employee = User.create!(name: "Employee")

    with_tenant(@tenant_a) do
      Loam::Membership.create!(user: @manager, role: "manager")
      Loam::Membership.create!(user: @employee, role: "employee")
    end
  end

  test "guardrail: records are invisible outside their tenant" do
    record_id = with_tenant(@tenant_a) { Equipment.create!(name: "Sample name 0", daily_rate: 9.99, status: "Sample status 0").id }

    with_tenant(@tenant_a) { assert_equal 1, Equipment.count }

    with_tenant(@tenant_b) do
      assert_equal 0, Equipment.count
      assert_raises(ActiveRecord::RecordNotFound) { Equipment.find(record_id) }
    end
  end

  test "guardrail: touching the model with no tenant context raises" do
    assert_raises(Loam::MissingTenantError) { Equipment.count }
    assert_raises(Loam::MissingTenantError) { Equipment.new }
  end

  test "guardrail: a record cannot be written into a foreign tenant" do
    record = with_tenant(@tenant_a) { Equipment.create!(name: "Sample name 0", daily_rate: 9.99, status: "Sample status 0") }

    with_tenant(@tenant_b) do
      assert_raises(Loam::MissingTenantError) { record.update!(name: "Sample name 1", daily_rate: 10.99, status: "Sample status 1") }
    end
  end

  test "every change is audited with actor and changeset" do
    with_tenant(@tenant_a, actor: @manager) do
      record = Equipment.create!(name: "Sample name 0", daily_rate: 9.99, status: "Sample status 0")

      audit = Loam::AuditRecord.find_by(
        auditable_type: "Equipment", auditable_id: record.id, action: "create"
      )
      assert audit, "expected an audit record for the create"
      assert_equal @manager.id, audit.actor_id
      assert_includes audit.changeset.keys, "name"
    end
  end

  test "lifecycle events are published with the tenant stamped" do
    received = []
    subscription = Loam::Events.subscribe("rental.equipment.created") do |_name, payload|
      received << payload
    end

    with_tenant(@tenant_a, actor: @manager) { Equipment.create!(name: "Sample name 0", daily_rate: 9.99, status: "Sample status 0") }

    assert_equal 1, received.size
    assert_equal @tenant_a.id, received.first[:tenant_id]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  test "policy: only members of the current tenant may act" do
    record = with_tenant(@tenant_a) { Equipment.create!(name: "Sample name 0", daily_rate: 9.99, status: "Sample status 0") }

    with_tenant(@tenant_a) do
      assert EquipmentPolicy.new(@manager, record).update?

      outsider = User.create!(name: "Outsider")
      outsider_policy = EquipmentPolicy.new(outsider, record)
      refute outsider_policy.update?
      refute outsider_policy.writable?(:name)
    end
  end
end
