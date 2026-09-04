require "test_helper"

# Does the tenant lifecycle actually work in an app that was built by the
# generators, as opposed to in the gem's own unit tests?
#
# The claim under test is the one the installed initializer makes: a block
# registered with OpenLoam.on_tenant_created runs when a tenant is created, runs
# inside that tenant's context, and — because `bin/rails open_loam:sync` re-runs it
# for every existing tenant — reaches tenants that already existed when the
# block was added. That last part is the whole reason sync exists: it is how a
# default introduced by a later release lands in an old tenant.
#
# This test gets its own app rather than sharing the smoke test's, because it
# edits the initializer. A test that mutates config has no business running
# against the tree whose whole point is to be a virgin install.
class LifecycleTest < HarnessCase
  # An idempotent seed, appended to the installed initializer the way a real
  # app would write one. find_or_create_by! is the contract OpenLoam::Lifecycle
  # documents; if sync were not idempotent this same block would raise or
  # duplicate on the second run, which is exactly what the assertions below
  # would catch.
  SEED_HOOK = <<~RUBY.freeze

    # Appended by the OpenLoam harness.
    OpenLoam.on_tenant_created do |tenant|
      OpenLoam::FieldDefinition.find_or_create_by!(entity_type: "Gadget", name: "asset_tag") do |definition|
        definition.field_type = "string"
      end
    end
  RUBY

  def test_on_tenant_created_fires_on_create_and_open_loam_sync_backfills_existing_tenants
    app = build_app(name: "open_loam_lifecycle_app")

    step("rails g open_loam:install", "bin/rails g open_loam:install", app)
    step("rails db:migrate", "bin/rails db:migrate", app)
    step("rails g open_loam:entity Gadget", "bin/rails g open_loam:entity Gadget name:string --domain lab", app)
    step("rails db:migrate (entity)", "bin/rails db:migrate", app)

    # A tenant that predates the hook. This is the "already existed when the
    # feature shipped" case that sync is for.
    create_tenant("old", app)
    assert_equal 0, seeded_fields("old", app),
                 "a tenant created before any hook was registered should have been seeded with nothing"

    # Now the app declares its seed, as a real app would: at file scope in
    # config/initializers/open_loam.rb.
    File.write(File.join(app, "config/initializers/open_loam.rb"), SEED_HOOK, mode: "a")

    # (1) The hook fires on create...
    create_tenant("new", app)
    assert_equal 1, seeded_fields("new", app),
                 "OpenLoam.on_tenant_created did not run when the tenant was created"

    # ...and it ran inside THAT tenant's context, not whatever context happened
    # to be current. The block never mentions tenant_id, so a correct tenant_id
    # can only have come from OpenLoam.as_tenant.
    assert_equal tenant_id("new", app), field_tenant_id("new", app),
                 "the seeded record was not stamped with the tenant the hook was running for"

    # The pre-existing tenant is untouched until someone syncs.
    assert_equal 0, seeded_fields("old", app),
                 "creating one tenant seeded a different tenant — the hook is leaking across tenant context"

    # (2) sync backfills the old tenant and leaves the new one alone.
    sync = step("rails open_loam:sync", "bin/rails open_loam:sync", app)
    assert_match(/tenant/i, sync.output,
                 "open_loam:sync produced no report of what it did#{sync.failure_report}")

    assert_equal 1, seeded_fields("old", app),
                 "bin/rails open_loam:sync did not backfill the tenant that predated the hook#{sync.failure_report}"
    assert_equal 1, seeded_fields("new", app),
                 "bin/rails open_loam:sync duplicated the seed in a tenant that already had it#{sync.failure_report}"

    # (3) Idempotence is the documented contract, so syncing again must be a
    # no-op rather than a second row or a uniqueness violation.
    resync = step("rails open_loam:sync (again)", "bin/rails open_loam:sync", app)
    assert_equal 1, seeded_fields("old", app), "a second open_loam:sync duplicated the seed#{resync.failure_report}"
    assert_equal 1, seeded_fields("new", app), "a second open_loam:sync duplicated the seed#{resync.failure_report}"
  end

  private

  def create_tenant(slug, app)
    runner("create tenant #{slug}", %(OpenLoam::Tenant.create!(name: "Tenant #{slug}", slug: "#{slug}")), app)
  end

  # Everything below reads real rows out of the generated app's database. Going
  # through `bin/rails runner` rather than opening the SQLite file directly is
  # deliberate: it exercises the app's own boot, initializer included.
  def seeded_fields(slug, app)
    runner_integer("count seeds in #{slug}", in_tenant(slug, "OpenLoam::FieldDefinition.count"), app)
  end

  def tenant_id(slug, app)
    runner_integer("tenant id #{slug}", %(OpenLoam::Tenant.find_by!(slug: "#{slug}").id), app)
  end

  def field_tenant_id(slug, app)
    runner_integer("seed tenant_id in #{slug}", in_tenant(slug, "OpenLoam::FieldDefinition.first.tenant_id"), app)
  end

  # Reads of a tenant-scoped model need a tenant in context or they raise, by
  # design — so every query here goes through the blessed switch.
  def in_tenant(slug, expression)
    %(OpenLoam.as_tenant(OpenLoam::Tenant.find_by!(slug: "#{slug}")) { #{expression} })
  end
end
