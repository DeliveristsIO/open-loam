require "test_helper"

# Generated guardrail tests for Equipment. They prove the OpenLoam
# invariants hold for THIS entity: tenant isolation, loud failure without
# context, audit-by-default, lifecycle events, membership-gated policies.
# Extend freely; never delete.
class EquipmentOpenLoamTest < ActiveSupport::TestCase
  setup do
    @tenant_a = OpenLoam::Tenant.create!(name: "Tenant A", slug: "a-equipment")
    @tenant_b = OpenLoam::Tenant.create!(name: "Tenant B", slug: "b-equipment")
    @manager = User.create!(name: "Manager", email: "manager@example.test", password: "password")
    @employee = User.create!(name: "Employee", email: "employee@example.test", password: "password")

    with_tenant(@tenant_a) do
      OpenLoam::Membership.create!(user: @manager, role: "manager")
      OpenLoam::Membership.create!(user: @employee, role: "employee")
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
    assert_raises(OpenLoam::MissingTenantError) { Equipment.count }
    assert_raises(OpenLoam::MissingTenantError) { Equipment.new }
  end

  test "guardrail: a record cannot be written into a foreign tenant" do
    record = with_tenant(@tenant_a) { Equipment.create!(name: "Sample name 0", daily_rate: 9.99, status: "Sample status 0") }

    with_tenant(@tenant_b) do
      assert_raises(OpenLoam::MissingTenantError) { record.update!(name: "Sample name 1", daily_rate: 10.99, status: "Sample status 1") }
    end
  end

  test "every change is audited with actor and changeset" do
    with_tenant(@tenant_a, actor: @manager) do
      record = Equipment.create!(name: "Sample name 0", daily_rate: 9.99, status: "Sample status 0")

      audit = OpenLoam::AuditRecord.find_by(
        auditable_type: "Equipment", auditable_id: record.id, action: "create"
      )
      assert audit, "expected an audit record for the create"
      assert_equal @manager.id, audit.actor_id
      assert_includes audit.changeset.keys, "name"
    end
  end

  test "lifecycle events are published with the tenant stamped" do
    received = []
    subscription = OpenLoam::Events.subscribe("rental.equipment.created") do |_name, payload|
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

      outsider = User.create!(name: "Outsider", email: "outsider@example.test", password: "password")
      outsider_policy = EquipmentPolicy.new(outsider, record)
      refute outsider_policy.update?
      refute outsider_policy.writable?(:name)
    end
  end
end
