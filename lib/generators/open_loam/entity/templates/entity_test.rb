require "test_helper"

# Generated guardrail tests for <%= class_name %>. They prove the OpenLoam
# invariants hold for THIS entity: tenant isolation, loud failure without
# context, audit-by-default, lifecycle events, membership-gated policies.
# Extend freely; never delete.
class <%= class_name %>OpenLoamTest < ActiveSupport::TestCase
  setup do
    @tenant_a = OpenLoam::Tenant.create!(name: "Tenant A", slug: "a-<%= file_name %>")
    @tenant_b = OpenLoam::Tenant.create!(name: "Tenant B", slug: "b-<%= file_name %>")
    @manager = User.create!(name: "Manager", email: "manager@example.test", password: "password")
    @employee = User.create!(name: "Employee", email: "employee@example.test", password: "password")

    with_tenant(@tenant_a) do
      OpenLoam::Membership.create!(user: @manager, role: "manager")
      OpenLoam::Membership.create!(user: @employee, role: "employee")
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
    assert_raises(OpenLoam::MissingTenantError) { <%= class_name %>.count }
    assert_raises(OpenLoam::MissingTenantError) { <%= class_name %>.new }
  end

  test "guardrail: a record cannot be written into a foreign tenant" do
    record = with_tenant(@tenant_a) { <%= class_name %>.create!(<%= sample_attributes %>) }

    with_tenant(@tenant_b) do
      assert_raises(OpenLoam::MissingTenantError) { record.update!(<%= sample_attributes(1) %>) }
    end
  end

  test "every change is audited with actor and changeset" do
    with_tenant(@tenant_a, actor: @manager) do
      record = <%= class_name %>.create!(<%= sample_attributes %>)

      audit = OpenLoam::AuditRecord.find_by(
        auditable_type: "<%= class_name %>", auditable_id: record.id, action: "create"
      )
      assert audit, "expected an audit record for the create"
      assert_equal @manager.id, audit.actor_id
      assert_includes audit.changeset.keys, "<%= first_field %>"
    end
  end

  test "lifecycle events are published with the tenant stamped" do
    received = []
    subscription = OpenLoam::Events.subscribe("<%= domain %>.<%= singular_name %>.created") do |_name, payload|
      received << payload
    end

    with_tenant(@tenant_a, actor: @manager) { <%= class_name %>.create!(<%= sample_attributes %>) }

    assert_equal 1, received.size
    assert_equal @tenant_a.id, received.first[:tenant_id]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  test "soft-delete hides a record by default, stays tenant-scoped, and restores" do
    record_id = with_tenant(@tenant_a, actor: @manager) do
      record = <%= class_name %>.create!(<%= sample_attributes %>)
      record.soft_delete
      record.id
    end

    with_tenant(@tenant_a) do
      assert_equal 0, <%= class_name %>.count, "a soft-deleted record is gone from ordinary queries"
      assert_equal 1, <%= class_name %>.with_deleted.count, "but the row still exists"
      assert OpenLoam::AuditRecord.exists?(auditable_type: "<%= class_name %>", auditable_id: record_id, action: "soft_delete")
    end

    # with_deleted lifts the deleted_at filter but NOT the tenant filter.
    with_tenant(@tenant_b) do
      assert_equal 0, <%= class_name %>.with_deleted.count, "the recycle bin must never cross tenants"
    end

    with_tenant(@tenant_a) do
      <%= class_name %>.with_deleted.find(record_id).restore
      assert_equal 1, <%= class_name %>.count, "restore returns the record to the default scope"
    end
  end

  test "policy: only members of the current tenant may act" do
    record = with_tenant(@tenant_a) { <%= class_name %>.create!(<%= sample_attributes %>) }

    with_tenant(@tenant_a) do
      assert <%= class_name %>Policy.new(@manager, record).update?

      outsider = User.create!(name: "Outsider", email: "outsider@example.test", password: "password")
      outsider_policy = <%= class_name %>Policy.new(outsider, record)
      refute outsider_policy.update?
      refute outsider_policy.writable?(:<%= first_field %>)
    end
  end
end
