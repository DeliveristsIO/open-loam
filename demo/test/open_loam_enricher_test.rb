require "test_helper"

# OpenLoam::Enrichers: attach a computed block onto another module's entity at read
# time, no foreign-key coupling. The registry is process-global, so each test
# snapshots it in setup and restores in teardown (keeping the app's boot-
# registered Equipment enricher intact).
class OpenLoamEnricherTest < ActiveSupport::TestCase
  setup do
    @snapshot = OpenLoam::Enrichers.snapshot
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-enrich")
    @krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-enrich")
  end

  teardown { OpenLoam::Enrichers.restore(@snapshot) }

  test "register and enrich returns the computed block for a record" do
    OpenLoam::Enrichers.restore({})
    OpenLoam::Enrichers.register("Equipment", key: "label") { |equipment| "#{equipment.name} (#{equipment.status})" }

    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")
      assert_equal({ "label" => "Digger (available)" }, OpenLoam::Enrichers.enrich(equipment))
    end
  end

  test "enrich_many with a batch resolver issues ONE query for N records (no N+1)" do
    OpenLoam::Enrichers.restore({})
    OpenLoam::Enrichers.register("Equipment", key: "reports", batch: lambda { |equipments|
      counts = DamageReport.where(equipment_id: equipments.map(&:id), state: "pending_approval").group(:equipment_id).count
      equipments.map(&:id).index_with { |id| counts.fetch(id, 0) }
    })

    with_tenant(@warsaw) do
      equipments = Array.new(3) { |i| Equipment.create!(name: "E#{i}", daily_rate: 10, status: "available") }
      equipments.each_with_index { |e, i| (i + 1).times { DamageReport.create!(equipment_id: e.id, description: "x", state: "pending_approval") } }

      result = nil
      queries = count_queries { result = OpenLoam::Enrichers.enrich_many(equipments) }

      assert_equal 1, queries, "the batch resolver resolves all N in a single query"
      # ...AND the values are right, correctly keyed per record (1, 2, 3 reports).
      equipments.each_with_index do |equipment, i|
        assert_equal i + 1, result.dig(equipment.id, "reports"), "each record gets its own count"
      end
    end
  end

  test "a per-record enricher costs one query per record (the N+1 the batch path avoids)" do
    OpenLoam::Enrichers.restore({})
    OpenLoam::Enrichers.register("Equipment", key: "reports") { |e| DamageReport.where(equipment_id: e.id, state: "pending_approval").count }

    with_tenant(@warsaw) do
      equipments = Array.new(3) { |i| Equipment.create!(name: "E#{i}", daily_rate: 10, status: "available") }

      queries = count_queries { OpenLoam::Enrichers.enrich_many(equipments) }
      assert_operator queries, :>, 1, "per-record resolution is N queries, more than the batch path's 1"
    end
  end

  test "a raising enricher is isolated: its key is omitted, others still resolve" do
    OpenLoam::Enrichers.restore({})
    OpenLoam::Enrichers.register("Equipment", key: "boom") { raise "kaboom" }
    OpenLoam::Enrichers.register("Equipment", key: "ok") { 42 }

    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")
      result = OpenLoam::Enrichers.enrich(equipment)

      refute result.key?("boom"), "the failing enricher's key is omitted"
      assert_equal 42, result["ok"], "and the others still resolve"
    end
  end

  test "on a same-key collision, higher priority wins" do
    OpenLoam::Enrichers.restore({})
    OpenLoam::Enrichers.register("Equipment", key: "tier", priority: 0) { "low" }
    OpenLoam::Enrichers.register("Equipment", key: "tier", priority: 5) { "high" }

    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")
      assert_equal "high", OpenLoam::Enrichers.enrich(equipment)["tier"]
    end
  end

  test "enrichers only ever see the current tenant's data" do
    OpenLoam::Enrichers.restore({})
    OpenLoam::Enrichers.register("Equipment", key: "reports") { |e| DamageReport.where(equipment_id: e.id, state: "pending_approval").count }

    equipment_id = with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Shared", daily_rate: 100, status: "available")
      2.times { DamageReport.create!(equipment_id: equipment.id, description: "warsaw", state: "pending_approval") }
      equipment.id
    end
    # A Krakow report with the SAME equipment_id must not be counted.
    with_tenant(@krakow) { DamageReport.create!(equipment_id: equipment_id, description: "krakow", state: "pending_approval") }

    with_tenant(@warsaw) do
      assert_equal 2, OpenLoam::Enrichers.enrich(Equipment.find(equipment_id))["reports"], "only Warsaw's reports count"
    end
  end

  test "enrich_many refuses a mix of entity types" do
    with_tenant(@warsaw) do
      equipment = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")
      report = DamageReport.create!(equipment_id: equipment.id, description: "x", state: "open")

      assert_raises(ArgumentError) { OpenLoam::Enrichers.enrich_many([ equipment, report ]) }
    end
  end

  private

  def count_queries
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if payload[:name].to_s =~ /SCHEMA|TRANSACTION|CACHE/ || payload[:cached]
      next if payload[:sql].to_s =~ /\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE|PRAGMA)/i

      count += 1
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end

# The enrichments appear in the JSON API payload, separate from the record's
# own attributes (using the demo's boot-registered Equipment enricher).
class ApiEnricherTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-enrich-api")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    with_tenant(@tenant) do
      OpenLoam::Membership.create!(user: @anna, role: "manager")
      @token = OpenLoam::ApiToken.create!(user: @anna, label: "ops").token
      @excavator = Equipment.create!(name: "Excavator", daily_rate: 900, status: "available")
      DamageReport.create!(equipment_id: @excavator.id, description: "cracked", state: "pending_approval")
    end
  end

  test "an entity's API response carries enrichments under a separate key" do
    get "/api/equipment/#{@excavator.id}", headers: { "Authorization" => "Bearer #{@token}" }
    assert_response :success

    body = response.parsed_body
    assert_equal "Excavator", body["name"], "the record's own attributes are top-level"
    assert body.key?("enrichments"), "computed blocks live under 'enrichments'"
    assert_equal 1, body.dig("enrichments", "open_damage_reports")
    refute body.key?("open_damage_reports"), "an enrichment is never mixed into the attributes"
  end
end
