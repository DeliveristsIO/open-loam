require "test_helper"

# Search: a substring match over the columns an entity declares, returned as an
# ordinary relation — so it is tenant-scoped without doing anything about it.
#
# These certify the DEFAULT LikeDriver specifically, so they pin it (the demo
# opts into the TokenDriver in its initializer). The TokenDriver has its own
# class below.
class LoamSearchTest < ActiveSupport::TestCase
  setup do
    @previous_driver = Loam::Search.driver
    Loam::Search.driver = Loam::Search::LikeDriver

    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-search")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-search")

    with_tenant(@warsaw) do
      Equipment.create!(name: "Excavator CAT 320", daily_rate: 950, status: "available")
      Equipment.create!(name: "Concrete mixer", daily_rate: 120, status: "rented")
    end

    with_tenant(@krakow) { Equipment.create!(name: "Excavator CAT 400", daily_rate: 990, status: "available") }
  end

  teardown { Loam::Search.driver = @previous_driver }

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

# The TokenDriver: a portable word-level index (loam_search_tokens). Word-level,
# order-independent, AND semantics, tenant-scoped, index maintained on write —
# and NEVER tokenizing an encrypted field's plaintext.
class LoamTokenSearchTest < ActiveSupport::TestCase
  setup do
    @previous_driver = Loam::Search.driver
    Loam::Search.driver = Loam::Search::TokenDriver

    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-token")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-token")

    with_tenant(@warsaw) do
      @excavator = Equipment.create!(name: "Excavator CAT 320", daily_rate: 950, status: "available")
      @mixer = Equipment.create!(name: "Concrete mixer", daily_rate: 120, status: "rented")
    end
    with_tenant(@krakow) { Equipment.create!(name: "Excavator CAT 400", daily_rate: 990, status: "available") }
  end

  teardown { Loam::Search.driver = @previous_driver }

  test "matches on whole words, order-independent (unlike a substring LIKE)" do
    with_tenant(@warsaw) do
      assert_equal [ "Excavator CAT 320" ], Equipment.search("excavator cat").pluck(:name)
      assert_equal [ "Excavator CAT 320" ], Equipment.search("cat excavator").pluck(:name), "word order does not matter"
      assert_equal [ "Concrete mixer" ], Equipment.search("mixer").pluck(:name)
    end
  end

  test "AND semantics: every query word must be present" do
    with_tenant(@warsaw) do
      assert_empty Equipment.search("excavator mixer").pluck(:name), "no record carries both words"
      assert_equal [ "Excavator CAT 320" ], Equipment.search("excavator 320").pluck(:name)
    end
  end

  test "a blank query filters nothing" do
    with_tenant(@warsaw) do
      assert_equal 2, Equipment.search("").count
      assert_equal 2, Equipment.search("   ").count
    end
  end

  test "tokens are tenant-scoped: a Warsaw word never matches from Krakow" do
    with_tenant(@warsaw) { assert_equal [ "Excavator CAT 320" ], Equipment.search("320").pluck(:name) }
    with_tenant(@krakow) do
      assert_empty Equipment.search("320").pluck(:name), "320 is a Warsaw excavator"
      assert_equal [ "Excavator CAT 400" ], Equipment.search("400").pluck(:name)
    end
  end

  test "the index is maintained on update" do
    with_tenant(@warsaw) do
      @excavator.update!(name: "Backhoe loader")

      assert_empty Equipment.search("excavator").pluck(:name), "the old word is gone"
      assert_equal [ "Backhoe loader" ], Equipment.search("backhoe").pluck(:name), "the new word is found"
    end
  end

  test "the index is maintained on destroy" do
    with_tenant(@warsaw) do
      assert_operator Loam::SearchToken.where(searchable_type: "Equipment", searchable_id: @mixer.id).count, :>, 0
      @mixer.destroy!
      assert_equal 0, Loam::SearchToken.where(searchable_type: "Equipment", searchable_id: @mixer.id).count
      assert_empty Equipment.search("mixer").pluck(:name)
    end
  end

  test "reindex rebuilds a model's tokens from scratch" do
    with_tenant(@warsaw) do
      Loam::SearchToken.where(searchable_type: "Equipment").delete_all
      assert_empty Equipment.search("excavator").pluck(:name), "no tokens, no matches"

      Loam::Search.reindex(Equipment)
      assert_equal [ "Excavator CAT 320" ], Equipment.search("excavator").pluck(:name)
    end
  end

  test "an encrypted field's plaintext NEVER lands in the token index" do
    with_tenant(@warsaw) do
      customer = Customer.create!(name: "Acme Construction", email: "orders@acme.test", tax_id: "PL5260001246")
      tokens = Loam::SearchToken.where(searchable_type: "Customer", searchable_id: customer.id).pluck(:token)

      assert_equal %w[acme construction], tokens.sort, "only the searchable name is tokenized"
      refute tokens.any? { |t| t.include?("5260") }, "the encrypted tax_id must not be tokenized"
      refute tokens.any? { |t| t.include?("orders") || t.include?("acme.test") }, "the encrypted email must not be tokenized"
      assert_empty Customer.search("5260001246").pluck(:name), "the ciphertext is not searchable text"
    end
  end

  test "a soft-deleted record does not surface in search" do
    with_tenant(@warsaw) do
      @excavator.soft_delete!
      assert_empty Equipment.search("excavator").pluck(:name), "the base scope hides the deleted row"

      @excavator.restore!
      assert_equal [ "Excavator CAT 320" ], Equipment.search("excavator").pluck(:name), "restore brings it back with no reindex"
    end
  end
end

# The seam itself: one Model.search call site, swapped driver, different match
# behavior — proving a driver change touches NO caller.
class LoamSearchDriverSeamTest < ActiveSupport::TestCase
  setup do
    @previous_driver = Loam::Search.driver
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-seam")
  end

  teardown { Loam::Search.driver = @previous_driver }

  test "the same search call site behaves per the active driver, unchanged" do
    with_tenant(@warsaw) do
      Loam::Search.driver = Loam::Search::TokenDriver
      equipment = Equipment.create!(name: "Excavator CAT 320", daily_rate: 950, status: "available")

      # LIKE: substring, mid-word.
      Loam::Search.driver = Loam::Search::LikeDriver
      assert_equal [ "Excavator CAT 320" ], Equipment.search("xcav").pluck(:name), "LIKE matches a substring"

      # Token: whole words only — a mid-word fragment does not match, but the
      # reordered words do. Same call site, no code change.
      Loam::Search.driver = Loam::Search::TokenDriver
      assert_empty Equipment.search("xcav").pluck(:name), "the token driver is word-level, not substring"
      assert_equal [ "Excavator CAT 320" ], Equipment.search("320 excavator").pluck(:name)
    end
  end
end
