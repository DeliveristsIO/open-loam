require "test_helper"

# Loam::Configs: a global default plus per-tenant overrides, resolved
# override → global row → declared default, and never leaking across tenants.
class LoamConfigTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-config")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-config")
  end

  test "a declared default resolves when there is no global row or override" do
    # rental.currency is declared in config/initializers/loam.rb, with no row.
    with_tenant(@warsaw) do
      assert_equal "PLN", Loam::Configs.get("rental.currency")
    end
    assert_equal "PLN", Loam::Configs.get("rental.currency"), "declared default resolves with no tenant too"
  end

  test "the global row wins over the declared default, for every tenant" do
    Loam::Configs.set("billing.retention_days", 90, scope: :global)

    with_tenant(@warsaw) { assert_equal 90, Loam::Configs.get("billing.retention_days") }
    with_tenant(@krakow) { assert_equal 90, Loam::Configs.get("billing.retention_days") }
  end

  test "a tenant override wins over the global row" do
    Loam::Configs.set("billing.retention_days", 90, scope: :global)
    with_tenant(@warsaw) { Loam::Configs.set("billing.retention_days", 30) }

    with_tenant(@warsaw) do
      assert_equal 30, Loam::Configs.get("billing.retention_days")
      assert Loam::Configs.overridden?("billing.retention_days")
    end
  end

  test "a tenant override does not leak to another tenant" do
    Loam::Configs.set("billing.retention_days", 90, scope: :global)
    with_tenant(@warsaw) { Loam::Configs.set("billing.retention_days", 30) }

    with_tenant(@krakow) do
      assert_equal 90, Loam::Configs.get("billing.retention_days"), "Krakow sees the global, not Warsaw's override"
      refute Loam::Configs.overridden?("billing.retention_days")
    end
  end

  test "setting a tenant override requires a tenant in context" do
    assert_raises(Loam::MissingTenantError) { Loam::Configs.set("x.y", 1) }
    assert_raises(Loam::MissingTenantError) { Loam::Configs.reset("x.y") }
  end

  test "reset removes the override so the key falls back to the global" do
    Loam::Configs.set("billing.retention_days", 90, scope: :global)
    with_tenant(@warsaw) do
      Loam::Configs.set("billing.retention_days", 30)
      assert_equal 30, Loam::Configs.get("billing.retention_days")

      Loam::Configs.reset("billing.retention_days")

      assert_equal 90, Loam::Configs.get("billing.retention_days")
      refute Loam::Configs.overridden?("billing.retention_days")
    end
  end

  test "values keep their type through a write and a fresh read" do
    with_tenant(@warsaw) do
      {
        "f.bool" => true,
        "f.int" => 42,
        "f.float" => 9.99,
        "f.string" => "net-30",
        "f.hash" => { "mode" => "strict", "grace" => 3 }
      }.each do |key, value|
        Loam::Configs.set(key, value)
        assert_equal value, Loam::Configs.get(key), "#{key} did not round-trip"
      end
    end
  end

  test "one global row per key — the partial unique index holds" do
    Loam::Config.create!(key: "dup.global", value_json: 1)

    # validate: false to hit the database, not the model validation, so this
    # proves the partial index rather than the AR uniqueness check.
    assert_raises(ActiveRecord::RecordNotUnique) do
      Loam::Config.new(key: "dup.global", tenant_id: nil, value_json: 2).save!(validate: false)
    end
  end

  test "one override row per key per tenant — the unique index holds" do
    with_tenant(@warsaw) { Loam::Configs.set("dup.override", 1) }

    assert_raises(ActiveRecord::RecordNotUnique) do
      Loam::Config.new(key: "dup.override", tenant_id: @warsaw.id, value_json: 2).save!(validate: false)
    end
  end

  test "defined_keys unions declared defaults with global and tenant rows" do
    Loam::Configs.set("z.global_only", 1, scope: :global)
    keys = with_tenant(@warsaw) do
      Loam::Configs.set("z.warsaw_only", 2)
      Loam::Configs.defined_keys
    end

    assert_includes keys, "rental.currency", "a declared default is a defined key even with no row"
    assert_includes keys, "z.global_only"
    assert_includes keys, "z.warsaw_only"
  end

  # Regression: the per-request cache key omits `default:`, so an unset key must
  # not cache the first caller's fallback and hand it to a later caller.
  test "an unset key never caches the caller's default argument" do
    with_tenant(@warsaw) do
      assert_equal 1, Loam::Configs.get("nothing.here", default: 1)
      assert_equal 2, Loam::Configs.get("nothing.here", default: 2), "the arg default must not be cached"
    end
  end
end

# The admin Settings screen: managers may change a setting, employees may not.
class AdminConfigsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-config-flow")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    @tomek = User.create!(name: "Tomek", email: "tomek@example.test", password: "password")

    with_tenant(@tenant) do
      Loam::Membership.create!(user: @anna, role: "manager")
      Loam::Membership.create!(user: @tomek, role: "employee")
    end
  end

  test "a manager can set a tenant override through the admin" do
    post admin_session_path, params: { email: "anna@example.test", password: "password" }

    # The screens render: the index lists declared keys, the edit form loads.
    get admin_configs_path
    assert_response :success
    assert_match "rental.late_fee_per_day", response.body

    get admin_edit_config_path(key: "rental.late_fee_per_day")
    assert_response :success

    patch admin_configs_path, params: { key: "rental.late_fee_per_day", value: "45" }
    assert_response :redirect

    with_tenant(@tenant) do
      assert_equal 45, Loam::Configs.get("rental.late_fee_per_day")
      assert Loam::Configs.overridden?("rental.late_fee_per_day")
    end
  end

  test "an employee is forbidden from the settings screen" do
    post admin_session_path, params: { email: "tomek@example.test", password: "password" }

    get admin_configs_path
    assert_response :forbidden

    patch admin_configs_path, params: { key: "rental.late_fee_per_day", value: "45" }
    assert_response :forbidden
  end
end
