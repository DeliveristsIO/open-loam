require "test_helper"

# L-919: custom-field index coverage + read-time gap detection → correct
# fallback + deduped async self-heal.
class LoamIndexCoverageTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Loam::CustomFieldIndex.reset_pending!
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-cov")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-cov")
    [ @warsaw, @krakow ].each do |t|
      with_tenant(t) { Loam::FieldDefinition.create!(entity_type: "Equipment", name: "grade", field_type: "string") }
    end
  end

  teardown { Loam::CustomFieldIndex.reset_pending! }

  def make(tenant, name, grade)
    with_tenant(tenant) do
      e = Equipment.create!(name: name, daily_rate: 1, status: "available")
      e.set_custom_field(:grade, grade); e.save!
      e
    end
  end

  test "coverage reports indexed vs expected" do
    make(@warsaw, "A", "alpha")
    make(@warsaw, "B", "beta")
    with_tenant(@warsaw) do
      c = Loam::CustomFieldIndex.coverage(Equipment, "grade")
      assert_equal 2, c[:expected]
      assert_equal 2, c[:indexed]
      assert c[:complete]
      assert Loam::CustomFieldIndex.covered?(Equipment, "grade")
    end
  end

  test "a gap → coverage incomplete → filter still returns CORRECT results (fallback) → reindex → complete" do
    a = make(@warsaw, "A", "alpha")
    make(@warsaw, "B", "beta")

    with_tenant(@warsaw) do
      # Simulate drift: the authoritative json still has the values, but the
      # index rows are gone (legacy data / a write that bypassed the hook).
      Loam::CustomFieldValue.delete_all
      refute Loam::CustomFieldIndex.covered?(Equipment, "grade"), "coverage sees the gap"

      result = Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "alpha")
      assert_equal [ a.id ], result.pluck(:id), "the JSON fallback returns the correct record, not a partial set"
      assert Loam::CustomFieldIndex.partial?, "and flags the result as served over an incomplete index"

      # Healing rebuilds coverage; then the query is index-backed and not partial.
      Loam::CustomFieldIndex.reindex(Equipment)
      assert Loam::CustomFieldIndex.covered?(Equipment, "grade")
      assert_equal [ a.id ], Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "alpha").pluck(:id)
      refute Loam::CustomFieldIndex.partial?
    end
  end

  test "a gappy read enqueues a reindex, deduped (a second read doesn't double-enqueue)" do
    make(@warsaw, "A", "alpha")
    with_tenant(@warsaw) do
      Loam::CustomFieldValue.delete_all

      assert_enqueued_jobs 1, only: Loam::CustomFieldReindexJob do
        Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "alpha")
        Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "beta") # same gappy field → no 2nd enqueue
      end
    end
  end

  test "a complete index serves index-backed and never enqueues a heal" do
    make(@warsaw, "A", "alpha")
    with_tenant(@warsaw) do
      assert_no_enqueued_jobs do
        result = Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "alpha")
        assert_equal [ "A" ], result.pluck(:name)
      end
      refute Loam::CustomFieldIndex.partial?
      assert_match "loam_custom_field_values", Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "alpha").to_sql
    end
  end

  test "the reindex job heals a tenant's gap and is tenant-scoped" do
    make(@warsaw, "WA", "shared")
    make(@krakow, "KA", "shared")
    with_tenant(@warsaw) { Loam::CustomFieldValue.where(indexable_type: "Equipment").delete_all }

    perform_enqueued_jobs { Loam::CustomFieldReindexJob.perform_now(@warsaw.id, "Equipment") }

    assert with_tenant(@warsaw) { Loam::CustomFieldIndex.covered?(Equipment, "grade") }, "Warsaw healed"
    assert_equal 1, with_tenant(@warsaw) { Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "shared").count }
    assert_equal 1, with_tenant(@krakow) { Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "shared").count }, "Krakow unaffected"
  end
end
