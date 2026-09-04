require "test_helper"

# Regression (#32): OpenLoam's Active Record layer is defined inside
# ActiveSupport.on_load(:active_record), so OpenLoam::TenantRecord exists only once
# something has referenced ActiveRecord::Base.
#
# Zeitwerk eager-loads app/models alphabetically. A host model inheriting from
# OpenLoam::TenantRecord that sorts ahead of application_record.rb reached the
# constant before anything had fired that hook, and eager load died with
# "uninitialized constant OpenLoam::TenantRecord". Whether an app hit it depended on
# its model names, so it surfaced on a rename rather than on the change that
# broke it — which is exactly the kind of failure a harness should own rather
# than leave to whichever app names a model badly enough to find it.
#
# This app is built to lose that race deliberately: Access sorts first, and
# nothing in the app touches Active Record ahead of it.
class EagerLoadOrderTest < HarnessCase
  def test_eager_load_succeeds_when_a_tenant_record_model_sorts_first
    app = build_app(name: "open_loam_eager_load_app")
    step("rails g open_loam:install", "bin/rails g open_loam:install", app)
    step("rails db:migrate", "bin/rails db:migrate", app)

    File.write(File.join(app, "app/models/access.rb"), <<~MODEL)
      class Access < OpenLoam::TenantRecord
      end
    MODEL

    # Proof the app can actually reproduce the bug. If some future template
    # adds a model sorting ahead of Access, Zeitwerk reaches Active Record
    # first, eager load passes for the wrong reason, and this test silently
    # stops testing anything.
    first = Dir[File.join(app, "app/models/*.rb")].map { |f| File.basename(f) }.min
    assert_equal "access.rb", first,
                 "this app was supposed to eager-load a OpenLoam::TenantRecord model first, but " \
                 "Zeitwerk will reach #{first} ahead of it — the regression cannot happen " \
                 "here and the test proves nothing"

    # zeitwerk:check eager-loads the whole app. Before the engine settled load
    # order this aborted with NameError on the line above.
    check = step("rails zeitwerk:check", "bin/rails zeitwerk:check", app)
    assert_match(/All is good!/, check.output,
                 "zeitwerk:check exited 0 without reporting success#{check.failure_report}")
  end
end
