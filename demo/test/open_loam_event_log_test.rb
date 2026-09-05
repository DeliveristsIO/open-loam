require "test_helper"

# The contract under test (OpenLoam::EventLog): capture is on by default and
# captures everything except a declared exclusion, rows are tenant-scoped and
# append-only, and retention prunes by age without tripping the append-only
# guard.
class OpenLoamEventLogTest < ActiveSupport::TestCase
  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-eventlog")
    @krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-eventlog")
  end

  test "a published event is captured as a row in its own tenant" do
    with_tenant(@warsaw) do
      OpenLoam::Events.publish("rental.equipment.inspected", { equipment_id: 42, note: "ok" })

      record = OpenLoam::EventRecord.sole
      assert_equal "rental.equipment.inspected", record.name
      assert_equal "42", record.payload_hash["equipment_id"].to_s
      assert_equal "ok", record.payload_hash["note"]
      assert record.occurred_at.present?
    end

    assert_equal 0, with_tenant(@krakow) { OpenLoam::EventRecord.count }, "captured events are tenant-scoped"
  end

  test "capture is on by default — nothing has to opt in" do
    with_tenant(@warsaw) do
      OpenLoam::Events.publish("billing.invoice.paid", { invoice_id: 7 })

      assert_equal 1, OpenLoam::EventRecord.count
    end
  end

  test "an excluded pattern is not captured" do
    with_tenant(@warsaw) do
      OpenLoam::Events.publish("open_loam.progress.tick", { pct: 10 })

      assert_equal 0, OpenLoam::EventRecord.count
    end
  end

  test "an event published with no tenant in context is not captured" do
    before = OpenLoam::EventRecord.unscoped.count
    OpenLoam::Events.publish("rental.orphan.happened", { foo: 1 })

    assert_equal before, OpenLoam::EventRecord.unscoped.count
  end

  test "a captured row is append-only" do
    with_tenant(@warsaw) do
      OpenLoam::Events.publish("rental.equipment.inspected", { equipment_id: 1 })
      record = OpenLoam::EventRecord.sole

      assert record.readonly?, "a persisted event row must be readonly — the log is evidence"
      assert_raises(ActiveRecord::ReadOnlyRecord) { record.update!(name: "tampered") }
    end
  end

  test "read filters by exact event name or domain prefix, oldest first" do
    with_tenant(@warsaw) do
      OpenLoam::Events.publish("rental.equipment.created", { id: 1 })
      OpenLoam::Events.publish("rental.equipment.inspected", { id: 2 })
      OpenLoam::Events.publish("billing.invoice.paid", { id: 3 })

      assert_equal %w[rental.equipment.created rental.equipment.inspected],
                   OpenLoam::EventLog.read("rental.").map(&:name)
      assert_equal %w[rental.equipment.created], OpenLoam::EventLog.read("rental.equipment.created").map(&:name)
      assert_equal 3, OpenLoam::EventLog.read.count, "no pattern reads the whole tenant log"
    end
  end

  test "a domain prefix containing an underscore matches its events" do
    # Regression: without an explicit ESCAPE clause this returned nothing, and
    # the demo has a damage_report domain — the common case, not an edge one.
    with_tenant(@warsaw) do
      OpenLoam::Events.publish("damage_report.claim.filed", { id: 1 })

      assert_equal %w[damage_report.claim.filed], OpenLoam::EventLog.read("damage_report.").map(&:name)
    end
  end

  test "an underscore in a domain prefix is literal, not a wildcard" do
    with_tenant(@warsaw) do
      OpenLoam::Events.publish("damagexreport.claim.filed", { id: 1 })

      assert_equal 0, OpenLoam::EventLog.read("damage_report.").count,
                   "`_` must match itself, not any character"
    end
  end

  test "replay hands a handler each captured event, in order" do
    with_tenant(@warsaw) do
      OpenLoam::Events.publish("billing.invoice.paid", { invoice_id: 7 })
      OpenLoam::Events.publish("billing.invoice.paid", { invoice_id: 8 })

      seen = []
      OpenLoam::EventLog.replay("billing.") { |name, payload| seen << [ name, payload["invoice_id"].to_s ] }

      assert_equal [ [ "billing.invoice.paid", "7" ], [ "billing.invoice.paid", "8" ] ], seen
    end
  end

  test "replay does not re-publish — a replayed event is not captured again" do
    with_tenant(@warsaw) do
      OpenLoam::Events.publish("billing.invoice.paid", { invoice_id: 7 })

      assert_no_difference -> { OpenLoam::EventRecord.count } do
        OpenLoam::EventLog.replay("billing.") { |_name, _payload| nil }
      end
    end
  end

  test "prune deletes past the retention window and keeps what is inside it" do
    with_tenant(@warsaw) do
      old = OpenLoam::EventRecord.create!(name: "rental.old.thing", payload: {}, occurred_at: 200.days.ago)
      recent = OpenLoam::EventRecord.create!(name: "rental.new.thing", payload: {}, occurred_at: 1.day.ago)

      assert_equal 1, OpenLoam::EventLog.prune
      assert_not OpenLoam::EventRecord.exists?(old.id)
      assert OpenLoam::EventRecord.exists?(recent.id)
    end
  end

  test "a nil retention keeps everything" do
    with_tenant(@warsaw) do
      OpenLoam::EventRecord.create!(name: "rental.ancient.thing", payload: {}, occurred_at: 5.years.ago)

      with_event_log_retention(nil) do
        assert_equal 0, OpenLoam::EventLog.prune
      end
      assert_equal 1, OpenLoam::EventRecord.count
    end
  end

  test "the prune job is tenant-scoped" do
    with_tenant(@warsaw) { OpenLoam::EventRecord.create!(name: "a.b.c", payload: {}, occurred_at: 200.days.ago) }
    with_tenant(@krakow) { OpenLoam::EventRecord.create!(name: "a.b.c", payload: {}, occurred_at: 200.days.ago) }

    OpenLoam::EventLogPruneJob.perform_now(tenant_id: @warsaw.id)

    assert_equal 0, with_tenant(@warsaw) { OpenLoam::EventRecord.count }
    assert_equal 1, with_tenant(@krakow) { OpenLoam::EventRecord.count }, "the prune must not cross tenants"
  end

  private

  def with_event_log_retention(duration)
    previous = OpenLoam.event_log_retention
    OpenLoam.event_log_retention = duration
    yield
  ensure
    OpenLoam.event_log_retention = previous
  end
end
