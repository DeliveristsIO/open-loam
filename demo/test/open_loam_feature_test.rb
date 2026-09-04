require "test_helper"

# Loam::Features: runtime capability toggles per tenant, built on Loam::Configs.
# A flag answers "is this turned on for this tenant right now", independent of
# who the user is — orthogonal to roles/policies.
class LoamFeatureTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-feature")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-feature")
  end

  test "a flag resolves to its declared default when no row exists" do
    # beta_dashboard is declared default:false in config/initializers/loam.rb.
    with_tenant(@warsaw) do
      refute Loam::Features.on?(:beta_dashboard)
      assert Loam::Features.off?(:beta_dashboard)
    end
  end

  test "a declared default of true resolves without any row" do
    Loam.feature_defaults["test.declared_on"] = { default: true, description: "on by default" }

    with_tenant(@warsaw) { assert Loam::Features.on?("test.declared_on") }
  ensure
    Loam.feature_defaults.delete("test.declared_on")
  end

  test "a global enable flips a flag on for every tenant" do
    Loam::Features.enable(:beta_dashboard, scope: :global)

    with_tenant(@warsaw) { assert Loam::Features.on?(:beta_dashboard) }
    with_tenant(@krakow) { assert Loam::Features.on?(:beta_dashboard) }
  end

  test "a tenant enable wins and does not leak to another tenant" do
    with_tenant(@warsaw) { Loam::Features.enable(:beta_dashboard) }

    with_tenant(@warsaw) do
      assert Loam::Features.on?(:beta_dashboard)
      assert Loam::Features.overridden?(:beta_dashboard)
    end
    with_tenant(@krakow) do
      refute Loam::Features.on?(:beta_dashboard), "Krakow must not see Warsaw's flag"
      refute Loam::Features.overridden?(:beta_dashboard)
    end
  end

  test "a tenant override can disable a globally-enabled flag" do
    Loam::Features.enable(:beta_dashboard, scope: :global)
    with_tenant(@warsaw) { Loam::Features.disable(:beta_dashboard) }

    with_tenant(@warsaw) { refute Loam::Features.on?(:beta_dashboard) }
    with_tenant(@krakow) { assert Loam::Features.on?(:beta_dashboard) }
  end

  test "reset drops the override so the flag falls back to the global state" do
    Loam::Features.enable(:beta_dashboard, scope: :global)
    with_tenant(@warsaw) do
      Loam::Features.disable(:beta_dashboard)
      refute Loam::Features.on?(:beta_dashboard)

      Loam::Features.reset(:beta_dashboard)

      assert Loam::Features.on?(:beta_dashboard), "falls back to the global enable"
      refute Loam::Features.overridden?(:beta_dashboard)
    end
  end

  test "enabling a tenant flag requires a tenant in context" do
    assert_raises(Loam::MissingTenantError) { Loam::Features.enable(:beta_dashboard) }
    assert_raises(Loam::MissingTenantError) { Loam::Features.disable(:beta_dashboard) }
    assert_raises(Loam::MissingTenantError) { Loam::Features.reset(:beta_dashboard) }
  end

  test "on? is memoized per request for a resolved value" do
    with_tenant(@warsaw) do
      # A flag backed by a real row caches; an UNSET flag resolving only to its
      # declared default is NOT cached (that is the caller's fallback — see the
      # Configs cache fix), so this proves memoization against a resolved value.
      Loam::Features.enable(:beta_dashboard, scope: :global)
      assert Loam::Features.on?(:beta_dashboard) # caches true for this request

      # Change the row straight in the DB, bypassing the cache-clearing API.
      Loam::Config.where(key: "features.beta_dashboard", tenant_id: nil).update_all(value_json: false)
      assert Loam::Features.on?(:beta_dashboard), "still true — served from the per-request cache"

      Loam::Current.config_cache = {} # as a fresh request would start
      refute Loam::Features.on?(:beta_dashboard)
    end
  end
end

# The admin Features screen and the require_feature! guard, end to end.
class AdminFeaturesFlowTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-feature-flow")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    @tomek = User.create!(name: "Tomek", email: "tomek@example.test", password: "password")

    with_tenant(@tenant) do
      Loam::Membership.create!(user: @anna, role: "manager")
      Loam::Membership.create!(user: @tomek, role: "employee")
    end
  end

  test "require_feature! 404s when off and allows once enabled" do
    post admin_session_path, params: { email: "anna@example.test", password: "password" }

    get admin_beta_dashboard_path
    assert_response :not_found, "the capability is off by default, so the page is not there"

    with_tenant(@tenant) { Loam::Features.enable(:beta_dashboard) }

    get admin_beta_dashboard_path
    assert_response :success
    assert_match "Beta dashboard", response.body
  end

  test "a manager can toggle a flag through the admin" do
    post admin_session_path, params: { email: "anna@example.test", password: "password" }

    get admin_features_path
    assert_response :success
    assert_match "beta_dashboard", response.body

    # Verify through real requests (each a fresh context): enabling makes the
    # gated page reachable, resetting takes it away again.
    post admin_enable_feature_path, params: { name: "beta_dashboard" }
    assert_response :redirect
    get admin_beta_dashboard_path
    assert_response :success

    delete admin_features_path, params: { name: "beta_dashboard" }
    assert_response :redirect
    get admin_beta_dashboard_path
    assert_response :not_found
  end

  test "an employee is forbidden from the features screen" do
    post admin_session_path, params: { email: "tomek@example.test", password: "password" }

    get admin_features_path
    assert_response :forbidden

    post admin_enable_feature_path, params: { name: "beta_dashboard" }
    assert_response :forbidden
  end
end
