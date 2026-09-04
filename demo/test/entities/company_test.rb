require "test_helper"

# Generated guardrail tests for Company. They prove the OpenLoam
# invariants hold for THIS entity: tenant isolation, loud failure without
# context, audit-by-default, lifecycle events, membership-gated policies.
# Extend freely; never delete.
class CompanyOpenLoamTest < ActiveSupport::TestCase
  setup do
    @tenant_a = OpenLoam::Tenant.create!(name: "Tenant A", slug: "a-company")
    @tenant_b = OpenLoam::Tenant.create!(name: "Tenant B", slug: "b-company")
    @manager = User.create!(name: "Manager", email: "manager@example.test", password: "password")
    @employee = User.create!(name: "Employee", email: "employee@example.test", password: "password")

    with_tenant(@tenant_a) do
      OpenLoam::Membership.create!(user: @manager, role: "manager")
      OpenLoam::Membership.create!(user: @employee, role: "employee")
    end
  end

  test "guardrail: records are invisible outside their tenant" do
    record_id = with_tenant(@tenant_a) { Company.create!(name: "Sample name 0", industry: "Sample industry 0", tier: "Sample tier 0").id }

    with_tenant(@tenant_a) { assert_equal 1, Company.count }

    with_tenant(@tenant_b) do
      assert_equal 0, Company.count
      assert_raises(ActiveRecord::RecordNotFound) { Company.find(record_id) }
    end
  end

  test "guardrail: touching the model with no tenant context raises" do
    assert_raises(OpenLoam::MissingTenantError) { Company.count }
    assert_raises(OpenLoam::MissingTenantError) { Company.new }
  end

  test "guardrail: a record cannot be written into a foreign tenant" do
    record = with_tenant(@tenant_a) { Company.create!(name: "Sample name 0", industry: "Sample industry 0", tier: "Sample tier 0") }

    with_tenant(@tenant_b) do
      assert_raises(OpenLoam::MissingTenantError) { record.update!(name: "Sample name 1", industry: "Sample industry 1", tier: "Sample tier 1") }
    end
  end

  test "every change is audited with actor and changeset" do
    with_tenant(@tenant_a, actor: @manager) do
      record = Company.create!(name: "Sample name 0", industry: "Sample industry 0", tier: "Sample tier 0")

      audit = OpenLoam::AuditRecord.find_by(
        auditable_type: "Company", auditable_id: record.id, action: "create"
      )
      assert audit, "expected an audit record for the create"
      assert_equal @manager.id, audit.actor_id
      assert_includes audit.changeset.keys, "name"
    end
  end

  test "lifecycle events are published with the tenant stamped" do
    received = []
    subscription = OpenLoam::Events.subscribe("crm.company.created") do |_name, payload|
      received << payload
    end

    with_tenant(@tenant_a, actor: @manager) { Company.create!(name: "Sample name 0", industry: "Sample industry 0", tier: "Sample tier 0") }

    assert_equal 1, received.size
    assert_equal @tenant_a.id, received.first[:tenant_id]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  test "soft-delete hides a record by default, stays tenant-scoped, and restores" do
    record_id = with_tenant(@tenant_a, actor: @manager) do
      record = Company.create!(name: "Sample name 0", industry: "Sample industry 0", tier: "Sample tier 0")
      record.soft_delete
      record.id
    end

    with_tenant(@tenant_a) do
      assert_equal 0, Company.count, "a soft-deleted record is gone from ordinary queries"
      assert_equal 1, Company.with_deleted.count, "but the row still exists"
      assert OpenLoam::AuditRecord.exists?(auditable_type: "Company", auditable_id: record_id, action: "soft_delete")
    end

    # with_deleted lifts the deleted_at filter but NOT the tenant filter.
    with_tenant(@tenant_b) do
      assert_equal 0, Company.with_deleted.count, "the recycle bin must never cross tenants"
    end

    with_tenant(@tenant_a) do
      Company.with_deleted.find(record_id).restore
      assert_equal 1, Company.count, "restore returns the record to the default scope"
    end
  end

  test "policy: only members of the current tenant may act" do
    record = with_tenant(@tenant_a) { Company.create!(name: "Sample name 0", industry: "Sample industry 0", tier: "Sample tier 0") }

    with_tenant(@tenant_a) do
      assert CompanyPolicy.new(@manager, record).update?

      outsider = User.create!(name: "Outsider", email: "outsider@example.test", password: "password")
      outsider_policy = CompanyPolicy.new(outsider, record)
      refute outsider_policy.update?
      refute outsider_policy.writable?(:name)
    end
  end
end
