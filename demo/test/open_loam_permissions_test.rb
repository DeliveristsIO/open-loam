require "test_helper"

# L-705: feature-string permissions with wildcards — a capability layer under the
# coarse role. Deny-by-default; `*` grants all, a trailing `.*` is a prefix.
class OpenLoamPermissionsTest < ActiveSupport::TestCase
  test "the wildcard matcher: exact, prefix, and all" do
    assert OpenLoam::Permissions.matches?("equipment.edit", "equipment.edit")
    refute OpenLoam::Permissions.matches?("equipment.edit", "equipment.read")

    assert OpenLoam::Permissions.matches?("equipment.*", "equipment.read")
    assert OpenLoam::Permissions.matches?("equipment.*", "equipment.deep.nested")
    assert OpenLoam::Permissions.matches?("equipment.*", "equipment")     # the bare stem too
    refute OpenLoam::Permissions.matches?("equipment.*", "billing.read")

    assert OpenLoam::Permissions.matches?("*", "anything.at.all")
  end

  test "allow? is deny-by-default and honors the demo grants" do
    # manager: "*"  employee: equipment.read + damage_report.*
    assert OpenLoam::Permissions.allow?(:manager, "billing.export")
    assert OpenLoam::Permissions.allow?(:employee, "equipment.read")
    assert OpenLoam::Permissions.allow?(:employee, "damage_report.approve")
    refute OpenLoam::Permissions.allow?(:employee, "equipment.edit")
    refute OpenLoam::Permissions.allow?(:clerk, "equipment.read"), "an unconfigured role is denied"
    refute OpenLoam::Permissions.allow?(nil, "equipment.read")
  end

  test "OpenLoam.can? resolves the current actor's role" do
    tenant = OpenLoam::Tenant.create!(name: "Branch", slug: "warsaw-perm")
    anna = User.create!(name: "Anna", email: "anna-perm@example.test", password: "password")
    tomek = User.create!(name: "Tomek", email: "tomek-perm@example.test", password: "password")
    with_tenant(tenant) do
      OpenLoam::Membership.create!(user: anna, role: "manager")
      OpenLoam::Membership.create!(user: tomek, role: "employee")
    end

    with_tenant(tenant, actor: anna) do
      assert OpenLoam.can?("equipment.edit")
      assert OpenLoam.can?("anything.goes")
    end
    with_tenant(tenant, actor: tomek) do
      assert OpenLoam.can?("equipment.read")
      refute OpenLoam.can?("equipment.edit")
    end
    with_tenant(tenant) do
      refute OpenLoam.can?("equipment.read"), "no actor → denied"
    end
  end

  test "grants are additive and de-duplicated" do
    OpenLoam::Permissions.role(:tester, allow: "reports.read")
    OpenLoam::Permissions.role(:tester, allow: %w[reports.read reports.export])
    assert_equal %w[reports.read reports.export], OpenLoam::Permissions.granted(:tester)
    assert OpenLoam::Permissions.allow?(:tester, "reports.export")
  ensure
    OpenLoam::Permissions.reset!
    # Re-apply the demo config the initializer set, so later tests still see it.
    OpenLoam::Permissions.configure do
      role :manager,  allow: "*"
      role :employee, allow: %w[equipment.read damage_report.*]
    end
  end
end
