require "test_helper"

# Regression (#31): the install and entity migrations spelled every key bigint
# — implicitly in create_table, and explicitly in t.references and the
# polymorphic *_id columns. In an app whose own tables use string or uuid keys
# the foreign keys did not line up with the tables they pointed at, so every
# generated migration had to be hand-edited after the generator ran.
#
# Two things are asserted here, and the second matters as much as the first:
# the generators follow a non-integer key, and an ordinary bigint app still
# gets exactly the migrations it got before. A regression that silently added
# `id:` to every table would reach every existing Loam app.
class PrimaryKeyTypeTest < HarnessCase
  def test_generators_follow_a_string_key_app_and_records_get_keys
    app = build_app(name: "loam_string_key_app")
    set_primary_key_type(app, ":string")

    step("rails g loam:install", "bin/rails g loam:install", app)

    body = File.read(migration(app, "create_loam_audit_records"))
    assert_match(/create_table :loam_audit_records, id: :string, limit: 36 do/, body,
                 "the table itself still declares a bigint key:\n#{body}")
    assert_match(/t\.references :tenant,.*type: :string, limit: 36/, body,
                 "the tenant foreign key does not match the tenants table:\n#{body}")
    # The polymorphic column cannot use t.references, so it is the one most
    # likely to be missed.
    assert_match(/t\.string :auditable_id, limit: 36/, body,
                 "the polymorphic key column is still a bigint:\n#{body}")

    step("rails db:migrate", "bin/rails db:migrate", app)
    step("rails g loam:entity Widget", "bin/rails g loam:entity Widget name:string", app)

    entity = File.read(migration(app, "create_widgets"))
    assert_match(/create_table :widgets, id: :string, limit: 36 do/, entity,
                 "loam:entity ignored the app's key type:\n#{entity}")

    step("rails db:migrate (entity)", "bin/rails db:migrate", app)

    # The migrations lining up is only half of it — a string key has no
    # database default, so without Loam::GeneratedKey the insert sends NULL.
    id = runner_value("create a tenant", %(Loam::Tenant.create!(name: "Acme", slug: "acme").id), app)
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, id,
                 "Loam::Tenant.create! did not generate a key, got #{id.inspect}")

    # The generated suite includes the tenant-isolation guardrails, which are
    # the thing most likely to break if keys stop comparing the way they did.
    step("bin/rails test (generated app)", "bin/rails test", app)
  end

  def test_a_default_app_still_gets_bigint_migrations
    app = build_app(name: "loam_bigint_key_app")
    step("rails g loam:install", "bin/rails g loam:install", app)

    offenders = Dir[File.join(app, "db/migrate/*.rb")].select do |file|
      next false if File.basename(file).include?("active_storage")

      File.read(file).match?(/\bid: :|\btype: :/)
    end
    assert_empty offenders.map { |f| File.basename(f) },
                 "an app that never asked for a key type got key options in its migrations — " \
                 "this changes the schema of every existing Loam app"

    step("rails db:migrate", "bin/rails db:migrate", app)
  end

  private

  def set_primary_key_type(app, type)
    path = File.join(app, "config/application.rb")
    source = File.read(path)
    anchor = source[/^\s*config\.load_defaults.*\n/] or
      flunk "no config.load_defaults line to anchor the generators config to"

    File.write(path, source.sub(anchor, <<~CONFIG))
      #{anchor}
          config.generators do |g|
            g.orm :active_record, primary_key_type: #{type}
          end
    CONFIG
  end

  def migration(app, name)
    Dir[File.join(app, "db/migrate/*#{name}.rb")].first or
      flunk "no #{name} migration was generated"
  end

  def runner_value(label, expression, app)
    output = runner(label, %(print "#{VALUE_SENTINEL}=#{'#{'}#{expression}#{'}'}"), app)
    match = output.match(/#{VALUE_SENTINEL}=(\S+)/)
    assert match, "expected a value from `#{expression}` in the generated app, got:\n#{output}"
    match[1]
  end
end
