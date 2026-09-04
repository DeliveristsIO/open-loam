require "test_helper"

# L-401: the generated admin index sorts by clickable columns and carries the
# full filter state (search / saved view / custom-field filter / sort) across
# pagination and export — and the sort column is whitelisted, so a crafted
# `sort` param can never reach ORDER BY.
class LoamIndexSortTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch", slug: "warsaw-sort")
    @anna = User.create!(name: "Anna", email: "anna-sort@example.test", password: "password")
    with_tenant(@tenant) do
      Loam::Membership.create!(user: @anna, role: "manager")
      Equipment.create!(name: "Zeta digger", daily_rate: 10, status: "available")
      Equipment.create!(name: "Alpha crane", daily_rate: 99, status: "available")
    end
    post admin_session_path, params: { email: "anna-sort@example.test", password: "password" }
    post select_tenant_admin_session_path, params: { tenant_id: @tenant.id }
  end

  test "sorting by a column orders the rows and toggling direction reverses them" do
    get "/admin/equipment", params: { sort: "name", dir: "asc" }
    assert_response :success
    assert_operator response.body.index("Alpha crane"), :<, response.body.index("Zeta digger"),
                     "name asc puts Alpha before Zeta"

    get "/admin/equipment", params: { sort: "name", dir: "desc" }
    assert_operator response.body.index("Zeta digger"), :<, response.body.index("Alpha crane"),
                     "name desc puts Zeta before Alpha"
  end

  test "sorting by a numeric column works" do
    get "/admin/equipment", params: { sort: "daily_rate", dir: "asc" }
    assert_response :success
    assert_operator response.body.index("Zeta digger"), :<, response.body.index("Alpha crane"),
                     "daily_rate asc puts the cheaper (Zeta, 10) before Alpha (99)"
  end

  test "a crafted sort param is ignored, not injected into ORDER BY" do
    get "/admin/equipment", params: { sort: "name); DROP TABLE loam_tenants;--", dir: "asc" }
    assert_response :success  # falls back to the default order, no SQL error, no 500
    assert Loam::Tenant.exists?(@tenant.id)
  end

  test "a crafted dir param cannot inject either" do
    get "/admin/equipment", params: { sort: "name", dir: "asc); DROP TABLE loam_tenants;--" }
    assert_response :success  # dir is constrained to asc/desc
  end

  test "the sort header link carries the active search term" do
    get "/admin/equipment", params: { q: "crane" }
    assert_response :success
    # the Name header sorts, and its link keeps q=crane so sorting doesn't drop the filter
    assert_match(/href="[^"]*sort=name[^"]*q=crane|href="[^"]*q=crane[^"]*sort=name/, response.body)
  end
end
