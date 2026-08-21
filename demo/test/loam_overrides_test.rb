require "test_helper"

# Loam::Overrides: disable/replace an entry in a Loam registry without forking.
class LoamOverridesTest < ActiveSupport::TestCase
  setup do
    @snapshot = Loam::Overrides.snapshot   # process-global — restore in teardown
    Loam::Overrides.reset!                 # a clean slate for this test's overrides
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-ov")
    @actor = User.create!(name: "A", email: "a@example.test", password: "password")
    Loam::Widgets.reset!
    Loam::Widgets.register(key: "keep", title: "Keep") { |_| { kind: "count", value: 1 } }
    Loam::Widgets.register(key: "drop", title: "Drop") { |_| { kind: "count", value: 2 } }
  end

  teardown do
    Loam::Overrides.restore(@snapshot)
    Loam::Widgets.reset!
    Loam::Widgets.register_builtins!
  end

  test "disable removes a widget from the dashboard" do
    Loam::Overrides.disable(:widgets, "drop")
    with_tenant(@tenant, actor: @actor) do
      keys = Loam::Dashboard.for(actor: @actor, role: :manager).map { |t| t[:key] }
      assert_includes keys, "keep"
      refute_includes keys, "drop", "the disabled widget is gone"
    end
  end

  test "replace swaps a widget's implementation" do
    Loam::Overrides.replace(:widgets, "keep") { |_actor| { kind: "count", value: 42 } }
    with_tenant(@tenant, actor: @actor) do
      tile = Loam::Widgets.resolve("keep", actor: @actor, role: :manager)
      assert_equal 42, tile[:data][:value], "the replacement provider ran, not the original"
    end
  end

  test "disabling a broadcast pattern stops that event reaching the SSE frame" do
    original = Loam.broadcast_events
    Loam.broadcast_events = [ "loam.progress.", "loam.notification." ]

    assert Loam::EventStream.broadcastable?("loam.progress.updated")
    Loam::Overrides.disable(:broadcast_events, "loam.progress.")
    refute Loam::EventStream.broadcastable?("loam.progress.updated"), "the disabled pattern no longer broadcasts"
    assert Loam::EventStream.broadcastable?("loam.notification.created"), "other patterns are unaffected"
  ensure
    Loam.broadcast_events = original
  end

  test "a stale override (unknown key) is detected by check! and warned about" do
    Loam::Overrides.disable(:widgets, "keep")            # real
    Loam::Overrides.disable(:widgets, "does_not_exist")  # stale

    stale = Loam::Overrides.stale
    assert_equal [ [ :widgets, "does_not_exist" ] ], stale, "only the unknown key is stale"

    warned = capture_warn { Loam::Overrides.check! }
    assert_match(/stale override/, warned)
    assert_match(/does_not_exist/, warned)
  end

  test "an override for a non-introspectable registry is not flagged stale" do
    Loam::Overrides.disable(:enrichers, "anything")  # we don't introspect enrichers -> not stale
    assert_empty Loam::Overrides.stale
  end

  private

  # check! logs via Rails.logger in the app; capture it for the assertion.
  def capture_warn
    io = StringIO.new
    original = Rails.logger
    Rails.logger = Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end
end
