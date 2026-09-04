require "test_helper"

# The end-to-end proof: a virgin Rails app, the two generators that are OpenLoam's
# entire interface, and the app's own test suite green afterwards.
#
# Why one test method rather than six: the steps are strictly sequential — you
# cannot migrate before installing, or run the suite before migrating — and
# Minitest randomises method order. Generating the app is also the expensive
# part, so it happens once and every later assertion reads the same tree.
#
# Everything asserted here is behaviour: exit statuses, files that exist,
# routes that still load. Nothing asserts what is *inside* a template, because
# templates are supposed to be edited freely without breaking this harness.
class GeneratorSmokeTest < HarnessCase
  # Files open_loam:install must put in the host app. Their contents are the
  # generator's business; their presence is the contract.
  INSTALL_ARTIFACTS = %w[
    AGENTS.md
    config/initializers/open_loam.rb
    app/models/user.rb
    app/controllers/admin/base_controller.rb
    app/controllers/admin/sessions_controller.rb
    app/controllers/admin/dashboard_controller.rb
    app/controllers/admin/field_definitions_controller.rb
    app/views/layouts/admin.html.erb
    test/open_loam_guardrails_test.rb
  ].freeze

  # Migrations are timestamped, so match by the part the generator controls.
  INSTALL_MIGRATIONS = %w[
    create_users
    create_open_loam_tenants
    create_open_loam_memberships
    create_open_loam_audit_records
    create_open_loam_field_definitions
  ].freeze

  ENTITY_ARTIFACTS = %w[
    app/models/gadget.rb
    app/policies/gadget_policy.rb
    app/controllers/admin/gadgets_controller.rb
    app/views/admin/gadgets/index.html.erb
    app/views/admin/gadgets/show.html.erb
    app/views/admin/gadgets/new.html.erb
    app/views/admin/gadgets/edit.html.erb
    app/views/admin/gadgets/_form.html.erb
    test/entities/gadget_test.rb
  ].freeze

  ENTITY_COMMAND = "bin/rails g open_loam:entity Gadget name:string price:decimal --domain lab"

  def test_open_loam_installs_into_a_brand_new_rails_app_and_leaves_it_green
    app = build_app

    # (a) install
    install = step("rails g open_loam:install", "bin/rails g open_loam:install", app, timeout: 180)

    missing = INSTALL_ARTIFACTS.reject { |f| File.file?(File.join(app, f)) }
    assert_empty missing, "open_loam:install did not create: #{missing.join(', ')}#{install.failure_report}"

    migrations = Dir[File.join(app, "db/migrate/*.rb")].map { |f| File.basename(f) }
    absent = INSTALL_MIGRATIONS.reject { |name| migrations.any? { |m| m.include?(name) } }
    assert_empty absent,
                 "no migration matching: #{absent.join(', ')} (found: #{migrations.join(', ')})#{install.failure_report}"

    # The install wires OpenLoam's test helpers into the host app's test_helper.rb
    # by injection, which is the step most likely to silently no-op when Rails
    # changes its generated test_helper.
    assert_includes File.read(File.join(app, "test/test_helper.rb")), "OpenLoam::TestHelpers",
                    "open_loam:install did not wire OpenLoam::TestHelpers into test/test_helper.rb#{install.failure_report}"

    # (b) migrate
    step("rails db:migrate (install)", "bin/rails db:migrate", app, timeout: 180)

    # (c) entity
    entity = step("rails g open_loam:entity Gadget", ENTITY_COMMAND, app, timeout: 180)

    missing = ENTITY_ARTIFACTS.reject { |f| File.file?(File.join(app, f)) }
    assert_empty missing, "open_loam:entity did not create: #{missing.join(', ')}#{entity.failure_report}"

    entity_migrations = Dir[File.join(app, "db/migrate/*_create_gadgets.rb")]
    assert_equal 1, entity_migrations.size,
                 "expected exactly one create_gadgets migration, got #{entity_migrations.size}#{entity.failure_report}"

    assert_match(/resources :gadgets/, File.read(File.join(app, "config/routes.rb")),
                 "open_loam:entity did not add the admin route for Gadget#{entity.failure_report}")

    # (d) migrate again
    step("rails db:migrate (entity)", "bin/rails db:migrate", app, timeout: 180)

    # (e) the generated app's own suite — this is what proves the guardrail
    # tests and the generated entity tests actually pass in a virgin app,
    # rather than merely existing.
    suite = step("bin/rails test (generated app)", "bin/rails test", app, timeout: 300)
    puts "\nGenerated app suite: #{summary_line(suite.output)}"

    # (f) idempotence: re-running the entity generator must not corrupt the
    # app. --skip makes collisions non-interactive; the point of the assertion
    # is the state afterwards, not this command's own exit status.
    rerun = attempt("rails g open_loam:entity Gadget (rerun)", "#{ENTITY_COMMAND} --skip", app)
    refute rerun.timed_out?, "the second open_loam:entity run hung — it is prompting on a file collision#{rerun.failure_report}"

    duplicates = Dir[File.join(app, "db/migrate/*_create_gadgets.rb")]
    assert_equal 1, duplicates.size,
                 "re-running open_loam:entity added a duplicate migration: #{duplicates.map { |f| File.basename(f) }.join(', ')}" \
                 "#{rerun.failure_report}"

    step("bin/rails routes (after rerun)", "bin/rails routes", app)
  end
end
