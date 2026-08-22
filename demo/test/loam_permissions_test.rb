require "test_helper"

# L-705: feature-string permissions with wildcards — a capability layer under the
# coarse role. Deny-by-default; `*` grants all, a trailing `.*` is a prefix.
class LoamPermissionsTest < ActiveSupport::TestCase
  test "the wildcard matcher: exact, prefix, and all" do
    assert Loam::Permissions.matches?("equipment.edit", "equipment.edit")
    refute Loam::Permissions.matches?("equipment.edit", "equipment.read")

    assert Loam::Permissions.matches?("equipment.*", "equipment.read")
    assert Loam::Permissions.matches?("equipment.*", "equipment.deep.nested")
    assert Loam::Permissions.matches?("equipment.*", "equipment")     # the bare stem too
    refute Loam::Permissions.matches?("equipment.*", "billing.read")

    assert Loam::Permissions.matches?("*", "anything.at.all")
  end

  test "allow? is deny-by-default and honors the demo grants" do
    # manager: "*"  employee: equipment.read + damage_report.*
    assert Loam::Permissions.allow?(:manager, "billing.export")
    assert Loam::Permissions.allow?(:employee, "equipment.read")
    assert Loam::Permissions.allow?(:employee, "damage_report.approve")
    refute Loam::Permissions.allow?(:employee, "equipment.edit")
    refute Loam::Permissions.allow?(:clerk, "equipment.read"), "an unconfigured role is denied"
    refute Loam::Permissions.allow?(nil, "equipment.read")
  end

  test "Loam.can? resolves the current actor's role" do
    tenant = Loam::Tenant.create!(name: "Branch", slug: "warsaw-perm")
    anna = User.create!(name: "Anna", email: "anna-perm@example.test", password: "password")
    tomek = User.create!(name: "Tomek", email: "tomek-perm@example.test", password: "password")
    with_tenant(tenant) do
      Loam::Membership.create!(user: anna, role: "manager")
      Loam::Membership.create!(user: tomek, role: "employee")
    end

    with_tenant(tenant, actor: anna) do
      assert Loam.can?("equipment.edit")
      assert Loam.can?("anything.goes")
    end
    with_tenant(tenant, actor: tomek) do
      assert Loam.can?("equipment.read")
      refute Loam.can?("equipment.edit")
    end
    with_tenant(tenant) do
      refute Loam.can?("equipment.read"), "no actor → denied"
    end
  end

  test "grants are additive and de-duplicated" do
    Loam::Permissions.role(:tester, allow: "reports.read")
    Loam::Permissions.role(:tester, allow: %w[reports.read reports.export])
    assert_equal %w[reports.read reports.export], Loam::Permissions.granted(:tester)
    assert Loam::Permissions.allow?(:tester, "reports.export")
  ensure
    Loam::Permissions.reset!
    # Re-apply the demo config the initializer set, so later tests still see it.
    Loam::Permissions.configure do
      role :manager,  allow: "*"
      role :employee, allow: %w[equipment.read damage_report.*]
    end
  end
end
