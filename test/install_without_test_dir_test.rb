require "test_helper"

# Regression: `rails new --skip-test` produces an app with no test/test_helper.rb.
#
# loam:install wires its helpers into that file, and it does so after it has
# already written migrations, models and the whole admin surface. When that
# injection assumed the file existed, the generator died at the last step and
# left a half-installed app behind — the worst possible outcome, because the
# app looks installed until you run it.
#
# What this asserts is the recovery, not the warning: the generator finishes,
# and everything that does not depend on a test directory is there.
class InstallWithoutTestDirTest < HarnessCase
  REQUIRED_AFTER_INSTALL = %w[
    AGENTS.md
    config/initializers/loam.rb
    app/models/user.rb
    app/controllers/admin/base_controller.rb
    app/controllers/admin/sessions_controller.rb
    app/controllers/admin/dashboard_controller.rb
    app/controllers/admin/field_definitions_controller.rb
    app/views/layouts/admin.html.erb
  ].freeze

  def test_install_completes_in_an_app_generated_without_a_test_directory
    app = build_app(name: "loam_no_test_app", extra_flags: %w[--skip-test])

    refute File.exist?(File.join(app, "test/test_helper.rb")),
           "this app was supposed to be built with --skip-test, but it has a test_helper.rb — " \
           "the regression it guards against cannot happen and the test proves nothing"

    install = step("rails g loam:install (no test dir)", "bin/rails g loam:install", app)

    missing = REQUIRED_AFTER_INSTALL.reject { |f| File.file?(File.join(app, f)) }
    assert_empty missing,
                 "loam:install stopped early and left a half-installed app — missing: #{missing.join(', ')}" \
                 "#{install.failure_report}"

    # Proof the generator took the guarded path rather than quietly getting
    # away with it: the guardrail test still landed (so it ran past the point
    # that used to be fatal), and it did not invent a test_helper.rb to inject
    # into. Asserted as state rather than as the warning's wording, which is
    # free to change.
    assert File.file?(File.join(app, "test/loam_guardrails_test.rb")),
           "the guardrail test was not written, so install stopped before it#{install.failure_report}"
    refute File.exist?(File.join(app, "test/test_helper.rb")),
           "loam:install fabricated a test_helper.rb in an app that opted out of tests#{install.failure_report}"

    migrations = Dir[File.join(app, "db/migrate/*.rb")]
    assert_equal 16, migrations.size,
                 "expected the sixteen install migrations, got #{migrations.map { |f| File.basename(f) }.join(', ')}" \
                 "#{install.failure_report}"

    # The real proof that the app is not half-dead: it still migrates and boots.
    step("rails db:migrate", "bin/rails db:migrate", app)
    step("bin/rails routes", "bin/rails routes", app)
  end
end
