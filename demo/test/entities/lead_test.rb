require "test_helper"

# Generated guardrail tests for Lead. They prove the Loam
# invariants hold for THIS entity: tenant isolation, loud failure without
# context, audit-by-default, lifecycle events, membership-gated policies.
# Extend freely; never delete.
class LeadLoamTest < ActiveSupport::TestCase
  setup do
    @tenant_a = Loam::Tenant.create!(name: "Tenant A", slug: "a-lead")
    @tenant_b = Loam::Tenant.create!(name: "Tenant B", slug: "b-lead")
    @manager = User.create!(name: "Manager", email: "manager@example.test", password: "password")
    @employee = User.create!(name: "Employee", email: "employee@example.test", password: "password")

    with_tenant(@tenant_a) do
      Loam::Membership.create!(user: @manager, role: "manager")
      Loam::Membership.create!(user: @employee, role: "employee")
    end
  end

  test "guardrail: records are invisible outside their tenant" do
    record_id = with_tenant(@tenant_a) { Lead.create!(company_id: 1, source: "Sample source 0", value: 9.99, state: "new").id }

    with_tenant(@tenant_a) { assert_equal 1, Lead.count }

    with_tenant(@tenant_b) do
      assert_equal 0, Lead.count
      assert_raises(ActiveRecord::RecordNotFound) { Lead.find(record_id) }
    end
  end

  test "guardrail: touching the model with no tenant context raises" do
    assert_raises(Loam::MissingTenantError) { Lead.count }
    assert_raises(Loam::MissingTenantError) { Lead.new }
  end

  test "guardrail: a record cannot be written into a foreign tenant" do
    record = with_tenant(@tenant_a) { Lead.create!(company_id: 1, source: "Sample source 0", value: 9.99, state: "new") }

    with_tenant(@tenant_b) do
      assert_raises(Loam::MissingTenantError) { record.update!(company_id: 2, source: "Sample source 1", value: 10.99, state: "new") }
    end
  end

  test "every change is audited with actor and changeset" do
    with_tenant(@tenant_a, actor: @manager) do
      record = Lead.create!(company_id: 1, source: "Sample source 0", value: 9.99, state: "new")

      audit = Loam::AuditRecord.find_by(
        auditable_type: "Lead", auditable_id: record.id, action: "create"
      )
      assert audit, "expected an audit record for the create"
      assert_equal @manager.id, audit.actor_id
      assert_includes audit.changeset.keys, "company_id"
    end
  end

  test "lifecycle events are published with the tenant stamped" do
    received = []
    subscription = Loam::Events.subscribe("crm.lead.created") do |_name, payload|
      received << payload
    end

    with_tenant(@tenant_a, actor: @manager) { Lead.create!(company_id: 1, source: "Sample source 0", value: 9.99, state: "new") }

    assert_equal 1, received.size
    assert_equal @tenant_a.id, received.first[:tenant_id]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  test "soft-delete hides a record by default, stays tenant-scoped, and restores" do
    record_id = with_tenant(@tenant_a, actor: @manager) do
      record = Lead.create!(company_id: 1, source: "Sample source 0", value: 9.99, state: "new")
      record.soft_delete
      record.id
    end

    with_tenant(@tenant_a) do
      assert_equal 0, Lead.count, "a soft-deleted record is gone from ordinary queries"
      assert_equal 1, Lead.with_deleted.count, "but the row still exists"
      assert Loam::AuditRecord.exists?(auditable_type: "Lead", auditable_id: record_id, action: "soft_delete")
    end

    # with_deleted lifts the deleted_at filter but NOT the tenant filter.
    with_tenant(@tenant_b) do
      assert_equal 0, Lead.with_deleted.count, "the recycle bin must never cross tenants"
    end

    with_tenant(@tenant_a) do
      Lead.with_deleted.find(record_id).restore
      assert_equal 1, Lead.count, "restore returns the record to the default scope"
    end
  end

  test "policy: only members of the current tenant may act" do
    record = with_tenant(@tenant_a) { Lead.create!(company_id: 1, source: "Sample source 0", value: 9.99, state: "new") }

    with_tenant(@tenant_a) do
      assert LeadPolicy.new(@manager, record).update?

      outsider = User.create!(name: "Outsider", email: "outsider@example.test", password: "password")
      outsider_policy = LeadPolicy.new(outsider, record)
      refute outsider_policy.update?
      refute outsider_policy.writable?(:company_id)
    end
  end
end
