require "test_helper"

# Generated guardrail tests for <%= class_name %>. They prove the Loam
# invariants hold for THIS entity: tenant isolation, loud failure without
# context, audit-by-default, lifecycle events, membership-gated policies.
# Extend freely; never delete.
class <%= class_name %>LoamTest < ActiveSupport::TestCase
  setup do
    @tenant_a = Loam::Tenant.create!(name: "Tenant A", slug: "a-<%= file_name %>")
    @tenant_b = Loam::Tenant.create!(name: "Tenant B", slug: "b-<%= file_name %>")
    @manager = User.create!(name: "Manager")
    @employee = User.create!(name: "Employee")

    with_tenant(@tenant_a) do
      Loam::Membership.create!(user: @manager, role: "manager")
      Loam::Membership.create!(user: @employee, role: "employee")
    end
  end

  test "guardrail: records are invisible outside their tenant" do
    record_id = with_tenant(@tenant_a) { <%= class_name %>.create!(<%= sample_attributes %>).id }

    with_tenant(@tenant_a) { assert_equal 1, <%= class_name %>.count }

    with_tenant(@tenant_b) do
      assert_equal 0, <%= class_name %>.count
      assert_raises(ActiveRecord::RecordNotFound) { <%= class_name %>.find(record_id) }
    end
  end

  test "guardrail: touching the model with no tenant context raises" do
    assert_raises(Loam::MissingTenantError) { <%= class_name %>.count }
    assert_raises(Loam::MissingTenantError) { <%= class_name %>.new }
  end

  test "guardrail: a record cannot be written into a foreign tenant" do
    record = with_tenant(@tenant_a) { <%= class_name %>.create!(<%= sample_attributes %>) }

    with_tenant(@tenant_b) do
      assert_raises(Loam::MissingTenantError) { record.update!(<%= sample_attributes(1) %>) }
    end
  end

  test "every change is audited with actor and changeset" do
    with_tenant(@tenant_a, actor: @manager) do
      record = <%= class_name %>.create!(<%= sample_attributes %>)

      audit = Loam::AuditRecord.find_by(
        auditable_type: "<%= class_name %>", auditable_id: record.id, action: "create"
      )
      assert audit, "expected an audit record for the create"
      assert_equal @manager.id, audit.actor_id
      assert_includes audit.changeset.keys, "<%= first_field %>"
    end
  end

  test "lifecycle events are published with the tenant stamped" do
    received = []
    subscription = Loam::Events.subscribe("<%= domain %>.<%= singular_name %>.created") do |_name, payload|
      received << payload
    end

    with_tenant(@tenant_a, actor: @manager) { <%= class_name %>.create!(<%= sample_attributes %>) }

    assert_equal 1, received.size
    assert_equal @tenant_a.id, received.first[:tenant_id]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  test "policy: only members of the current tenant may act" do
    record = with_tenant(@tenant_a) { <%= class_name %>.create!(<%= sample_attributes %>) }

    with_tenant(@tenant_a) do
      assert <%= class_name %>Policy.new(@manager, record).update?

      outsider = User.create!(name: "Outsider")
      outsider_policy = <%= class_name %>Policy.new(outsider, record)
      refute outsider_policy.update?
      refute outsider_policy.writable?(:<%= first_field %>)
    end
  end
end
