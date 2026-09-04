require "test_helper"

# Loam::CustomFieldIndex: the typed-EAV read model that makes custom-field
# filter/sort index-backed (not per-row JSON extraction).
class LoamCustomFieldIndexTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-cfi")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-cfi")
    [ @warsaw, @krakow ].each do |t|
      with_tenant(t) do
        Loam::FieldDefinition.create!(entity_type: "Equipment", name: "grade", field_type: "string")
        Loam::FieldDefinition.create!(entity_type: "Equipment", name: "weight", field_type: "integer")
      end
    end
  end

  def make(tenant, name, grade: nil, weight: nil)
    with_tenant(tenant) do
      e = Equipment.create!(name: name, daily_rate: 1, status: "available")
      e.set_custom_field(:grade, grade) if grade
      e.set_custom_field(:weight, weight) if weight
      e.save!
      e
    end
  end

  test "saving a record projects its custom fields into typed index rows" do
    e = make(@warsaw, "Rig", grade: "A", weight: 500)
    with_tenant(@warsaw) do
      rows = Loam::CustomFieldValue.where(indexable_type: "Equipment", indexable_id: e.id)
      assert_equal 2, rows.count
      assert_equal "500", rows.find_by(field_key: "weight").value_text
      assert_equal 500.0, rows.find_by(field_key: "weight").value_number, "cast into the numeric column"
    end
  end

  test "updating a custom field re-projects (old value gone, new present)" do
    e = make(@warsaw, "Rig", grade: "A")
    with_tenant(@warsaw) do
      assert_equal [ e.id ], Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "A").pluck(:id)
      e.set_custom_field(:grade, "B")
      e.save!
      assert_empty Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "A").pluck(:id)
      assert_equal [ e.id ], Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "B").pluck(:id)
    end
  end

  test "filter supports eq / numeric range / contains / present, index-backed" do
    a = make(@warsaw, "A", grade: "alpha", weight: 100)
    b = make(@warsaw, "B", grade: "beta",  weight: 900)

    with_tenant(@warsaw) do
      assert_equal [ a.id ], Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "alpha").pluck(:id)
      assert_equal [ b.id ], Loam::CustomFieldIndex.filter(Equipment, "weight", "gt", 500).pluck(:id)
      assert_equal [ a.id ], Loam::CustomFieldIndex.filter(Equipment, "grade", "contains", "lph").pluck(:id)
      assert_equal 2, Loam::CustomFieldIndex.filter(Equipment, "grade", "present").count

      # The query hits the index table, NOT a json extraction on custom_fields.
      sql = Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "alpha").to_sql
      assert_match "loam_custom_field_values", sql
      refute_match(/custom_fields/, sql, "no per-row JSON extraction")
    end
  end

  test "order-by an indexed custom field" do
    b = make(@warsaw, "B", grade: "b")
    a = make(@warsaw, "A", grade: "a")
    with_tenant(@warsaw) do
      assert_equal [ a.id, b.id ], Loam::CustomFieldIndex.order(Equipment, "grade", :asc).pluck(:id)
      assert_equal [ b.id, a.id ], Loam::CustomFieldIndex.order(Equipment, "grade", :desc).pluck(:id)
    end
  end

  test "filter is tenant-scoped: a Warsaw custom-field value never matches from Krakow" do
    make(@warsaw, "WarsawRig", grade: "shared")
    make(@krakow, "KrakowRig", grade: "shared")

    assert_equal 1, with_tenant(@warsaw) { Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "shared").count }
    assert_equal 1, with_tenant(@krakow) { Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "shared").count }
    warsaw_id = with_tenant(@warsaw) { Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "shared").first.name }
    assert_equal "WarsawRig", warsaw_id
  end

  test "a soft-deleted record drops out of the filter (base scope), destroy removes its rows" do
    e = make(@warsaw, "Rig", grade: "A")
    with_tenant(@warsaw) do
      e.soft_delete!
      assert_empty Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "A"), "hidden by the base scope"
      assert Loam::CustomFieldValue.where(indexable_id: e.id).exists?, "rows kept on soft-delete (restore brings it back)"

      e.destroy!
      refute Loam::CustomFieldValue.where(indexable_id: e.id).exists?, "hard destroy removes the rows"
    end
  end

  test "a key that is not a FieldDefinition is refused" do
    with_tenant(@warsaw) do
      assert_raises(Loam::Error) { Loam::CustomFieldIndex.filter(Equipment, "not_a_field", "eq", "x") }
      assert_raises(Loam::Error) { Loam::CustomFieldIndex.order(Equipment, "not_a_field") }
    end
  end

  test "reindex rebuilds a model's index rows from scratch" do
    e = make(@warsaw, "Rig", grade: "A")
    with_tenant(@warsaw) do
      Loam::CustomFieldValue.delete_all
      # L-919: a gappy filter still returns the correct record (JSON fallback),
      # never a silently-empty set.
      assert_equal [ e.id ], Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "A").pluck(:id)

      Loam::CustomFieldIndex.reindex(Equipment)
      assert Loam::CustomFieldValue.exists?(indexable_id: e.id, field_key: "grade"), "reindex rebuilt the row"
      assert_equal [ e.id ], Loam::CustomFieldIndex.filter(Equipment, "grade", "eq", "A").pluck(:id)
    end
  end
end

# The admin index filter routes a custom-field filter through the index.
class AdminCustomFieldFilterTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-cfi-adm")
    @mgr = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    with_tenant(@tenant) do
      Loam::Membership.create!(user: @mgr, role: "manager")
      Loam::FieldDefinition.create!(entity_type: "Equipment", name: "grade", field_type: "string")
      @a = Equipment.create!(name: "AlphaRig", daily_rate: 1, status: "available"); @a.set_custom_field(:grade, "alpha"); @a.save!
      @b = Equipment.create!(name: "BetaRig", daily_rate: 1, status: "available"); @b.set_custom_field(:grade, "beta"); @b.save!
    end
    post admin_session_path, params: { email: "anna@example.test", password: "password" }
  end

  test "the equipment index filters by a custom field through the read-model index" do
    get admin_equipment_index_path(cf_field: "grade", cf_value: "alpha")

    assert_response :success
    assert_match "AlphaRig", response.body
    refute_match "BetaRig", response.body
  end
end
