require "test_helper"

# OpenLoam::EventStream: the SSE bridge, tested at the PIECES — the allow-list, the
# tenant/audience filter, the SSE framing, and the in-process broadcaster
# (driven synchronously in the test thread). No test opens a live socket; the
# streaming endpoint itself is thin and covered by these collaborators.
class OpenLoamEventStreamTest < ActiveSupport::TestCase
  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-sse")
    @krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-sse")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    @bob = User.create!(name: "Bob", email: "bob@example.test", password: "password")
    @previous_broadcast = OpenLoam.broadcast_events
    OpenLoam.broadcast_events = [ "open_loam.notification." ]
  end

  teardown { OpenLoam.broadcast_events = @previous_broadcast }

  test "only events matching OpenLoam.broadcast_events are broadcastable (default off)" do
    assert OpenLoam::EventStream.broadcastable?("open_loam.notification.created")
    refute OpenLoam::EventStream.broadcastable?("rental.equipment.created"), "not in the allow-list"

    OpenLoam.broadcast_events = []
    refute OpenLoam::EventStream.broadcastable?("open_loam.notification.created"), "empty allow-list broadcasts nothing"
  end

  test "an event is deliverable only to the matching tenant" do
    payload = { tenant_id: @warsaw.id, user_id: @anna.id, id: 1 }

    assert OpenLoam::EventStream.deliverable?("open_loam.notification.created", payload, tenant: @warsaw, actor: @anna)
    refute OpenLoam::EventStream.deliverable?("open_loam.notification.created", payload, tenant: @krakow, actor: @anna),
           "a Warsaw event never reaches a Krakow stream"
  end

  test "a notification event reaches only its recipient; a non-recipient does not" do
    payload = { tenant_id: @warsaw.id, user_id: @anna.id, id: 1 }

    assert OpenLoam::EventStream.deliverable?("open_loam.notification.created", payload, tenant: @warsaw, actor: @anna)
    refute OpenLoam::EventStream.deliverable?("open_loam.notification.created", payload, tenant: @warsaw, actor: @bob),
           "Bob is not the recipient"
  end

  test "a non-broadcastable event is never deliverable" do
    payload = { tenant_id: @warsaw.id, user_id: @anna.id }
    refute OpenLoam::EventStream.deliverable?("rental.equipment.created", payload, tenant: @warsaw, actor: @anna)
  end

  test "the SSE frame is valid and carries no attribute values" do
    frame = OpenLoam::EventStream.frame("open_loam.notification.created",
                                    { id: 7, user_id: @anna.id, tenant_id: @warsaw.id, message: "secret content" })

    assert_match "event: open_loam.notification.created\n", frame
    assert frame.end_with?("\n\n"), "an SSE message ends with a blank line"

    data = JSON.parse(frame[/data: (.+)/, 1])
    assert_equal 7, data["id"]
    refute data.key?("message"), "no arbitrary payload content rides along"
    refute data.key?("tenant_id"), "tenant is implied by the connection, never sent"
  end

  test "the in-process broadcaster forwards only the events deliverable to a connection" do
    received = []
    handle = OpenLoam::EventStream.broadcaster.subscribe(tenant: @warsaw, actor: @anna) { |sse| received << sse }

    with_tenant(@warsaw) { OpenLoam::Events.publish("open_loam.notification.created", id: 1, user_id: @anna.id) }
    with_tenant(@krakow) { OpenLoam::Events.publish("open_loam.notification.created", id: 2, user_id: @anna.id) } # wrong tenant
    with_tenant(@warsaw) { OpenLoam::Events.publish("open_loam.notification.created", id: 3, user_id: @bob.id) }   # wrong recipient
    with_tenant(@warsaw) { OpenLoam::Events.publish("rental.equipment.created", id: 4) }                      # not broadcastable

    assert_equal 1, received.size, "only the Warsaw event addressed to Anna is forwarded"
    assert_match "open_loam.notification.created", received.first
  ensure
    OpenLoam::EventStream.broadcaster.unsubscribe(handle)
  end

  test "the broadcaster is a swappable seam" do
    assert_instance_of OpenLoam::EventStream::InProcessBroadcaster, OpenLoam::EventStream.broadcaster

    fake = Object.new
    OpenLoam::EventStream.broadcaster = fake
    assert_same fake, OpenLoam::EventStream.broadcaster, "a Redis/SolidCable broadcaster drops in with no call-site change"
  ensure
    OpenLoam::EventStream.broadcaster = OpenLoam::EventStream::InProcessBroadcaster.new
  end

  test "creating a notification publishes the live-bell event to its recipient" do
    received = []
    handle = OpenLoam::EventStream.broadcaster.subscribe(tenant: @warsaw, actor: @anna) { |sse| received << sse }

    with_tenant(@warsaw) { OpenLoam::Notifications.notify(@anna, title: "Something happened") }

    assert_equal 1, received.size, "the notification's after_create_commit event reached Anna's stream"
    assert_match "open_loam.notification.created", received.first
  ensure
    OpenLoam::EventStream.broadcaster.unsubscribe(handle)
  end
end
