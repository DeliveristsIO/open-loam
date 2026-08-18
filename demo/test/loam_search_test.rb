require "test_helper"

# Search: a substring match over the columns an entity declares, returned as an
# ordinary relation — so it is tenant-scoped without doing anything about it.
class LoamSearchTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-search")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-search")

    with_tenant(@warsaw) do
      Equipment.create!(name: "Excavator CAT 320", daily_rate: 950, status: "available")
      Equipment.create!(name: "Concrete mixer", daily_rate: 120, status: "rented")
    end

    with_tenant(@krakow) { Equipment.create!(name: "Excavator CAT 400", daily_rate: 990, status: "available") }
  end

  test "search matches a substring of any declared column" do
    with_tenant(@warsaw) do
      assert_equal [ "Excavator CAT 320" ], Equipment.search("CAT").pluck(:name)
      assert_equal [ "Concrete mixer" ], Equipment.search("mixer").pluck(:name), "matches mid-string, not only prefixes"
      assert_equal [ "Concrete mixer" ], Equipment.search("rented").pluck(:name), "status is declared searchable too"
    end
  end

  test "search ignores case" do
    with_tenant(@warsaw) do
      assert_equal [ "Excavator CAT 320" ], Equipment.search("excavator").pluck(:name)
      assert_equal [ "Excavator CAT 320" ], Equipment.search("ExCaVaToR").pluck(:name)
    end
  end

  test "a blank query filters nothing, so an empty search box is not an empty page" do
    with_tenant(@warsaw) do
      assert_equal 2, Equipment.search("").count
      assert_equal 2, Equipment.search(nil).count
      assert_equal 2, Equipment.search("   ").count
    end
  end

  test "LIKE wildcards in the query are matched literally" do
    with_tenant(@warsaw) do
      Equipment.create!(name: "50% scaffold", daily_rate: 10, status: "available")

      assert_equal [ "50% scaffold" ], Equipment.search("50%").pluck(:name)
      assert_empty Equipment.search("%%%%").pluck(:name), "a query of wildcards matches nothing, not everything"
      assert_empty Equipment.search("_xcavator").pluck(:name), "_ is a literal underscore, not a single-character wildcard"
    end
  end

  test "search never reaches into another tenant" do
    with_tenant(@warsaw) { assert_equal [ "Excavator CAT 320" ], Equipment.search("Excavator").pluck(:name) }
    with_tenant(@krakow) { assert_equal [ "Excavator CAT 400" ], Equipment.search("Excavator").pluck(:name) }
  end

  test "search composes with everything else a relation can do" do
    with_tenant(@warsaw) do
      assert_equal 1, Equipment.search("CAT").where(status: "available").count
      assert_equal 0, Equipment.search("CAT").where(status: "rented").count
    end
  end

  test "a model declares whether it is searchable at all" do
    assert Equipment.loam_searchable?
    assert_equal %w[name status], Equipment.loam_searchable_columns
    assert_equal %w[description state], DamageReport.loam_searchable_columns

    # Loam's own plumbing is not part of the app's search surface.
    refute Loam::Notification.respond_to?(:loam_searchable?)
  end
end
