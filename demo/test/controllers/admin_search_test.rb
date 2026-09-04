require "test_helper"

# The admin's two index primitives: one search box across every entity, and
# pagination on the per-entity lists.
class AdminSearchTest < ActionDispatch::IntegrationTest
  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-admin-search")
    @krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-admin-search")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password123")

    with_tenant(@warsaw) do
      OpenLoam::Membership.create!(user: @anna, role: "manager")
      Equipment.create!(name: "Excavator CAT 320", daily_rate: 950, status: "available")
      DamageReport.create!(equipment_id: 1, description: "Excavator boom cracked")
    end

    with_tenant(@krakow) do
      OpenLoam::Membership.create!(user: @anna, role: "manager")
      Equipment.create!(name: "Excavator CAT 400", daily_rate: 990, status: "available")
    end

    post admin_session_path, params: { email: "anna@example.test", password: "password123" }
    post select_tenant_admin_session_path, params: { tenant_id: @warsaw.id }
  end

  test "one query searches every searchable entity, grouped by kind" do
    get admin_search_path(q: "Excavator")

    assert_response :success
    assert_select "h2", text: "Equipment"
    assert_select "h2", text: "Damage reports"
    assert_match(/Excavator CAT 320/, response.body)
    assert_match(/Excavator boom cracked/, response.body)
  end

  test "search only ever finds the current tenant's records" do
    get admin_search_path(q: "Excavator")

    assert_no_match(/CAT 400/, response.body, "that excavator belongs to Krakow")
  end

  test "a query that matches nothing says so" do
    get admin_search_path(q: "helicopter")

    assert_response :success
    assert_match(/Nothing matches/, response.body)
  end

  test "the search box is on every admin screen" do
    get admin_root_path

    assert_select "nav form input[name=?]", "q"
  end

  test "an index page shows 25 records and a link to the rest" do
    with_tenant(@warsaw) do
      30.times { |i| Equipment.create!(name: "Drill #{i}", daily_rate: 10, status: "available") }
    end

    get admin_equipment_index_path
    assert_response :success
    assert_select "tbody tr", count: 25
    assert_select "a", text: "Next →"
    assert_select "a", text: "← Previous", count: 0

    get admin_equipment_index_path(page: 2)
    assert_select "tbody tr", { count: 6 }, "30 drills plus the excavator, minus the first 25"
    assert_select "a", text: "← Previous"
    assert_select "a", text: "Next →", count: 0
  end

  test "filtering an index narrows it, and the filter survives paging" do
    with_tenant(@warsaw) do
      30.times { |i| Equipment.create!(name: "Drill #{i}", daily_rate: 10, status: "available") }
    end

    get admin_equipment_index_path(q: "Excavator")
    assert_select "tbody tr", count: 1
    assert_select "a", text: "Next →", count: 0

    get admin_equipment_index_path(q: "Drill")
    assert_select "tbody tr", count: 25

    get admin_equipment_index_path(q: "Drill", page: 2)
    assert_select "tbody tr", { count: 5 }, "page 2 must still be filtered, not the whole list"
    assert_no_match(/Excavator/, response.body)
  end
end
