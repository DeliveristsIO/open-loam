require "test_helper"

# L-712: the observability seam. span() returns the block's value and, by default,
# emits an ActiveSupport::Notifications event; an app can replace the backend to
# emit real spans (OTLP, StatsD, …) with no change at the call sites.
class OpenLoamTelemetryTest < ActiveSupport::TestCase
  teardown { OpenLoam::Telemetry.reset! }

  test "span returns the block's value" do
    assert_equal 42, OpenLoam::Telemetry.span("thing", a: 1) { 42 }
  end

  test "by default it emits a open_loam.span.<name> notification with the attributes" do
    events = []
    sub = ActiveSupport::Notifications.subscribe("open_loam.span.work") do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end
    OpenLoam::Telemetry.span("work", tenant_id: 7) { :done }
    ActiveSupport::Notifications.unsubscribe(sub)

    assert_equal 1, events.size
    assert_equal 7, events.first.payload[:tenant_id]
  end

  test "a custom backend receives (name, attributes, work) and wraps the call" do
    calls = []
    OpenLoam::Telemetry.backend = ->(name, attributes, work) do
      calls << [ name, attributes ]
      work.call
    end

    result = OpenLoam::Telemetry.span("delivery", subscriber_key: "k") { "ran" }

    assert_equal "ran", result
    assert_equal [ [ "delivery", { subscriber_key: "k" } ] ], calls
  end

  test "the scheduler tick runs inside a span" do
    names = []
    OpenLoam::Telemetry.backend = ->(name, _attributes, work) do
      names << name
      work.call
    end
    OpenLoam::Scheduler.tick

    assert_includes names, "scheduler_tick"
  end
end
