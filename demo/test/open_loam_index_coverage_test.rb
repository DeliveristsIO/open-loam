require "test_helper"

# L-919: custom-field index coverage + read-time gap detection → correct
# fallback + deduped async self-heal.
class OpenLoamIndexCoverageTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    OpenLoam::CustomFieldIndex.reset_pending!
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-cov")
    @krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-cov")
    [ @warsaw, @krakow ].each do |t|
      with_tenant(t) { OpenLoam::FieldDefinition.create!(entity_type: "Equipment", name: "grade", field_type: "string") }
    end
  end

  teardown { OpenLoam::CustomFieldIndex.reset_pending! }

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
      c = OpenLoam::CustomFieldIndex.coverage(Equipment, "grade")
      assert_equal 2, c[:expected]
      assert_equal 2, c[:indexed]
      assert c[:complete]
      assert OpenLoam::CustomFieldIndex.covered?(Equipment, "grade")
    end
  end

  test "a gap → coverage incomplete → filter still returns CORRECT results (fallback) → reindex → complete" do
    a = make(@warsaw, "A", "alpha")
    make(@warsaw, "B", "beta")

    with_tenant(@warsaw) do
      # Simulate drift: the authoritative json still has the values, but the
      # index rows are gone (legacy data / a write that bypassed the hook).
      OpenLoam::CustomFieldValue.delete_all
      refute OpenLoam::CustomFieldIndex.covered?(Equipment, "grade"), "coverage sees the gap"

      result = OpenLoam::CustomFieldIndex.filter(Equipment, "grade", "eq", "alpha")
      assert_equal [ a.id ], result.pluck(:id), "the JSON fallback returns the correct record, not a partial set"
      assert OpenLoam::CustomFieldIndex.partial?, "and flags the result as served over an incomplete index"

      # Healing rebuilds coverage; then the query is index-backed and not partial.
      OpenLoam::CustomFieldIndex.reindex(Equipment)
      assert OpenLoam::CustomFieldIndex.covered?(Equipment, "grade")
      assert_equal [ a.id ], OpenLoam::CustomFieldIndex.filter(Equipment, "grade", "eq", "alpha").pluck(:id)
      refute OpenLoam::CustomFieldIndex.partial?
    end
  end

  test "a gappy read enqueues a reindex, deduped (a second read doesn't double-enqueue)" do
    make(@warsaw, "A", "alpha")
    with_tenant(@warsaw) do
      OpenLoam::CustomFieldValue.delete_all

      assert_enqueued_jobs 1, only: OpenLoam::CustomFieldReindexJob do
        OpenLoam::CustomFieldIndex.filter(Equipment, "grade", "eq", "alpha")
        OpenLoam::CustomFieldIndex.filter(Equipment, "grade", "eq", "beta") # same gappy field → no 2nd enqueue
      end
    end
  end

  test "a complete index serves index-backed and never enqueues a heal" do
    make(@warsaw, "A", "alpha")
    with_tenant(@warsaw) do
      assert_no_enqueued_jobs do
        result = OpenLoam::CustomFieldIndex.filter(Equipment, "grade", "eq", "alpha")
        assert_equal [ "A" ], result.pluck(:name)
      end
      refute OpenLoam::CustomFieldIndex.partial?
      assert_match "open_loam_custom_field_values", OpenLoam::CustomFieldIndex.filter(Equipment, "grade", "eq", "alpha").to_sql
    end
  end

  test "the reindex job heals a tenant's gap and is tenant-scoped" do
    make(@warsaw, "WA", "shared")
    make(@krakow, "KA", "shared")
    with_tenant(@warsaw) { OpenLoam::CustomFieldValue.where(indexable_type: "Equipment").delete_all }

    perform_enqueued_jobs { OpenLoam::CustomFieldReindexJob.perform_now(@warsaw.id, "Equipment") }

    assert with_tenant(@warsaw) { OpenLoam::CustomFieldIndex.covered?(Equipment, "grade") }, "Warsaw healed"
    assert_equal 1, with_tenant(@warsaw) { OpenLoam::CustomFieldIndex.filter(Equipment, "grade", "eq", "shared").count }
    assert_equal 1, with_tenant(@krakow) { OpenLoam::CustomFieldIndex.filter(Equipment, "grade", "eq", "shared").count }, "Krakow unaffected"
  end
end
