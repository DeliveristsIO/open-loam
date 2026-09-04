require "test_helper"

# Tenant lifecycle: a new tenant seeds itself from the OpenLoam.on_tenant_created
# blocks in config/initializers/open_loam.rb, and `bin/rails open_loam:sync`
# (OpenLoam.sync_tenants!) replays those same blocks for tenants that already
# exist — which only works because the blocks are idempotent.
class OpenLoamLifecycleTest < ActiveSupport::TestCase
  # Callbacks live in a process-wide registry, so a test that registers one
  # must remove it again or it fires for every later test in this worker.
  teardown { OpenLoam.tenant_created_callbacks.delete(@callback) if @callback }

  test "creating a tenant runs the callbacks inside that tenant's context" do
    seen = []
    @callback = OpenLoam.on_tenant_created { |tenant| seen << [ tenant.slug, OpenLoam.tenant!.id ] }

    tenant = OpenLoam::Tenant.create!(name: "Branch Gdansk", slug: "gdansk-lifecycle")

    assert_equal [ [ "gdansk-lifecycle", tenant.id ] ], seen,
      "expected the callback to run once, with the new tenant in OpenLoam::Current"
  end

  test "the app's own hook seeds a new tenant's default field definitions" do
    tenant = OpenLoam::Tenant.create!(name: "Branch Lodz", slug: "lodz-lifecycle")

    with_tenant(tenant) do
      definition = OpenLoam::FieldDefinition.find_by(entity_type: "Equipment", name: "asset_tag")
      assert definition, "expected config/initializers/open_loam.rb to seed asset_tag for a new tenant"
      assert_equal [ "manager" ], definition.writable_roles
    end
  end

  test "sync_tenants! backfills tenants created before a callback existed" do
    tenant = OpenLoam::Tenant.create!(name: "Branch Poznan", slug: "poznan-lifecycle")
    @callback = OpenLoam.on_tenant_created do |_tenant|
      OpenLoam::FieldDefinition.find_or_create_by!(entity_type: "Equipment", name: "insured_until") do |fd|
        fd.field_type = "date"
      end
    end

    with_tenant(tenant) do
      assert_nil OpenLoam::FieldDefinition.find_by(name: "insured_until"),
        "the callback was registered after this tenant existed, so nothing should have run for it yet"
    end

    assert_operator OpenLoam.sync_tenants!, :>=, 1

    with_tenant(tenant) { assert OpenLoam::FieldDefinition.find_by(name: "insured_until") }
  end

  test "sync_tenants! is idempotent — re-running creates nothing new" do
    tenant = OpenLoam::Tenant.create!(name: "Branch Wroclaw", slug: "wroclaw-lifecycle")

    OpenLoam.sync_tenants!
    OpenLoam.sync_tenants!

    with_tenant(tenant) do
      assert_equal 1, OpenLoam::FieldDefinition.where(entity_type: "Equipment", name: "asset_tag").count
    end
  end
end
