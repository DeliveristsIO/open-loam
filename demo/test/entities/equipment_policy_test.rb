require "test_helper"

# Business-specific policy rules for Equipment (on top of the generated
# guardrail tests): only managers may change prices or delete equipment.
class EquipmentPolicyTest < ActiveSupport::TestCase
  setup do
    @tenant = OpenLoam::Tenant.create!(name: "Branch A", slug: "branch-a")
    @manager = User.create!(name: "Manager", email: "manager@example.test", password: "password")
    @employee = User.create!(name: "Employee", email: "employee@example.test", password: "password")

    with_tenant(@tenant) do
      OpenLoam::Membership.create!(user: @manager, role: "manager")
      OpenLoam::Membership.create!(user: @employee, role: "employee")
      @excavator = Equipment.create!(name: "Excavator", daily_rate: 500.0, status: "available")
    end
  end

  test "an employee cannot write daily_rate; a manager can" do
    with_tenant(@tenant) do
      refute EquipmentPolicy.new(@employee, @excavator).writable?(:daily_rate)
      assert EquipmentPolicy.new(@manager, @excavator).writable?(:daily_rate)
    end
  end

  test "the permit list strips daily_rate for an employee, so it cannot be smuggled in via params" do
    with_tenant(@tenant) do
      fields = %i[name daily_rate status]
      assert_equal %i[name status], EquipmentPolicy.new(@employee, @excavator).permitted_fields(fields)
      assert_equal fields, EquipmentPolicy.new(@manager, @excavator).permitted_fields(fields)
    end
  end

  test "only a manager may destroy equipment" do
    with_tenant(@tenant) do
      refute EquipmentPolicy.new(@employee, @excavator).destroy?
      assert EquipmentPolicy.new(@manager, @excavator).destroy?
    end
  end
end
