require "test_helper"

# Loam::Widgets (registry) + Loam::Dashboard (per-tenant, role-visible layout).
class LoamWidgetTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-widget")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-widget")
    @actor = User.create!(name: "A", email: "a@example.test", password: "password")
    Loam::Widgets.reset!
  end

  # Restore the boot-time built-in widgets for the rest of the suite.
  teardown { Loam::Widgets.reset!; Loam::Widgets.register_builtins! }

  test "the dashboard renders the tenant's configured widgets in order" do
    Loam::Widgets.register(key: "a", title: "A") { |_| { kind: "count", value: 1 } }
    Loam::Widgets.register(key: "b", title: "B") { |_| { kind: "count", value: 2 } }

    with_tenant(@warsaw, actor: @actor) do
      Loam::DashboardWidget.create!(widget_key: "b", position: 1)
      Loam::DashboardWidget.create!(widget_key: "a", position: 2)

      tiles = Loam::Dashboard.for(actor: @actor, role: :manager)
      assert_equal %w[b a], tiles.map { |t| t[:key] }, "configured order wins"
    end
  end

  test "the default set (every registered widget) renders when unconfigured" do
    Loam::Widgets.register(key: "a", title: "A") { |_| { kind: "count", value: 1 } }
    Loam::Widgets.register(key: "b", title: "B") { |_| { kind: "count", value: 2 } }

    with_tenant(@krakow, actor: @actor) do
      assert_equal %w[a b], Loam::Dashboard.for(actor: @actor, role: :manager).map { |t| t[:key] }
    end
  end

  test "a role-restricted widget is hidden AND its data is never computed for that role" do
    computed = false
    Loam::Widgets.register(key: "secret", title: "Secret", roles: %w[manager]) do |_|
      computed = true
      { kind: "count", value: 42 }
    end

    with_tenant(@warsaw, actor: @actor) do
      tiles = Loam::Dashboard.for(actor: @actor, role: :employee)
      assert_empty tiles.select { |t| t[:key] == "secret" }, "employee doesn't see it"
      refute computed, "and its provider was never called (no data leaked)"

      Loam::Dashboard.for(actor: @actor, role: :manager)
      assert computed, "a manager does compute it"
    end
  end

  test "a raising widget is isolated into an error tile; the others still render" do
    Loam::Widgets.register(key: "ok", title: "OK") { |_| { kind: "count", value: 1 } }
    Loam::Widgets.register(key: "boom", title: "Boom") { |_| raise "kaboom" }

    with_tenant(@warsaw, actor: @actor) do
      tiles = Loam::Dashboard.for(actor: @actor, role: :manager)
      boom = tiles.find { |t| t[:key] == "boom" }
      assert_equal "kaboom", boom[:error]
      assert tiles.find { |t| t[:key] == "ok" }[:data], "the healthy widget still rendered"
    end
  end

  test "a widget's data is current-tenant only" do
    Loam::Widgets.register(key: "equipment_count", title: "Equipment") { |_| { kind: "count", value: Equipment.count } }
    with_tenant(@warsaw, actor: @actor) { 3.times { |i| Equipment.create!(name: "W#{i}", daily_rate: 1, status: "available") } }
    with_tenant(@krakow, actor: @actor) { Equipment.create!(name: "K", daily_rate: 1, status: "available") }

    warsaw_value = with_tenant(@warsaw, actor: @actor) { Loam::Widgets.resolve("equipment_count", actor: @actor, role: :manager)[:data][:value] }
    krakow_value = with_tenant(@krakow, actor: @actor) { Loam::Widgets.resolve("equipment_count", actor: @actor, role: :manager)[:data][:value] }
    assert_equal 3, warsaw_value, "counts only Warsaw"
    assert_equal 1, krakow_value, "counts only Krakow"
  end

  test "config is per tenant: Warsaw's layout doesn't apply to Krakow" do
    Loam::Widgets.register(key: "a", title: "A") { |_| { kind: "count", value: 1 } }
    Loam::Widgets.register(key: "b", title: "B") { |_| { kind: "count", value: 2 } }
    with_tenant(@warsaw, actor: @actor) { Loam::DashboardWidget.create!(widget_key: "b", position: 1) }

    warsaw = with_tenant(@warsaw, actor: @actor) { Loam::Dashboard.for(actor: @actor, role: :manager).map { |t| t[:key] } }
    krakow = with_tenant(@krakow, actor: @actor) { Loam::Dashboard.for(actor: @actor, role: :manager).map { |t| t[:key] } }
    assert_equal %w[b], warsaw
    assert_equal %w[a b], krakow, "Krakow has no config -> the default set"
  end

  test "the built-in widgets register and resolve" do
    Loam::Widgets.register_builtins!
    with_tenant(@warsaw, actor: @actor) do
      Loam::Membership.create!(user: @actor, role: "manager")
      tiles = Loam::Dashboard.for(actor: @actor, role: :manager)
      assert_includes tiles.map { |t| t[:key] }, "audit_recent"
      assert_includes tiles.map { |t| t[:key] }, "pending_approvals"
    end
  end
end

# The dashboard settings screen.
class AdminDashboardWidgetsTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-dw-admin")
    @mgr = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    @emp = User.create!(name: "Tomek", email: "tomek@example.test", password: "password")
    with_tenant(@tenant) do
      Loam::Membership.create!(user: @mgr, role: "manager")
      Loam::Membership.create!(user: @emp, role: "employee")
    end
  end

  def sign_in(email)
    post admin_session_path, params: { email: email, password: "password" }
  end

  test "the dashboard renders widget tiles" do
    sign_in("anna@example.test")
    get admin_root_path
    assert_response :success
    assert_select ".widget"
  end

  test "a manager configures the dashboard; an employee cannot" do
    sign_in("anna@example.test")
    patch admin_dashboard_widgets_path, params: { widgets: { "audit_recent" => { active: "1", position: "5" } } }
    assert_redirected_to admin_root_path
    assert_equal 5, with_tenant(@tenant) { Loam::DashboardWidget.find_by(widget_key: "audit_recent").position }

    sign_in("tomek@example.test")
    get admin_dashboard_widgets_path
    assert_response :forbidden
  end
end
