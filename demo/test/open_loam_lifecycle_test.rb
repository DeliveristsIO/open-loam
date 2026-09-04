require "test_helper"

# Tenant lifecycle: a new tenant seeds itself from the Loam.on_tenant_created
# blocks in config/initializers/loam.rb, and `bin/rails loam:sync`
# (Loam.sync_tenants!) replays those same blocks for tenants that already
# exist — which only works because the blocks are idempotent.
class LoamLifecycleTest < ActiveSupport::TestCase
  # Callbacks live in a process-wide registry, so a test that registers one
  # must remove it again or it fires for every later test in this worker.
  teardown { Loam.tenant_created_callbacks.delete(@callback) if @callback }

  test "creating a tenant runs the callbacks inside that tenant's context" do
    seen = []
    @callback = Loam.on_tenant_created { |tenant| seen << [ tenant.slug, Loam.tenant!.id ] }

    tenant = Loam::Tenant.create!(name: "Branch Gdansk", slug: "gdansk-lifecycle")

    assert_equal [ [ "gdansk-lifecycle", tenant.id ] ], seen,
      "expected the callback to run once, with the new tenant in Loam::Current"
  end

  test "the app's own hook seeds a new tenant's default field definitions" do
    tenant = Loam::Tenant.create!(name: "Branch Lodz", slug: "lodz-lifecycle")

    with_tenant(tenant) do
      definition = Loam::FieldDefinition.find_by(entity_type: "Equipment", name: "asset_tag")
      assert definition, "expected config/initializers/loam.rb to seed asset_tag for a new tenant"
      assert_equal [ "manager" ], definition.writable_roles
    end
  end

  test "sync_tenants! backfills tenants created before a callback existed" do
    tenant = Loam::Tenant.create!(name: "Branch Poznan", slug: "poznan-lifecycle")
    @callback = Loam.on_tenant_created do |_tenant|
      Loam::FieldDefinition.find_or_create_by!(entity_type: "Equipment", name: "insured_until") do |fd|
        fd.field_type = "date"
      end
    end

    with_tenant(tenant) do
      assert_nil Loam::FieldDefinition.find_by(name: "insured_until"),
        "the callback was registered after this tenant existed, so nothing should have run for it yet"
    end

    assert_operator Loam.sync_tenants!, :>=, 1

    with_tenant(tenant) { assert Loam::FieldDefinition.find_by(name: "insured_until") }
  end

  test "sync_tenants! is idempotent — re-running creates nothing new" do
    tenant = Loam::Tenant.create!(name: "Branch Wroclaw", slug: "wroclaw-lifecycle")

    Loam.sync_tenants!
    Loam.sync_tenants!

    with_tenant(tenant) do
      assert_equal 1, Loam::FieldDefinition.where(entity_type: "Equipment", name: "asset_tag").count
    end
  end
end
