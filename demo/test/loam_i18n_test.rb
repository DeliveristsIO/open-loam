require "test_helper"

# L-713: Loam's own UI strings are i18n-friendly. The gem ships a `loam.*` base
# locale (English); an app overrides per locale; the admin switcher drives BOTH
# the content overlay (Loam::Translatable) and the chrome (Rails i18n).
class LoamI18nTest < ActiveSupport::TestCase
  test "the gem's base loam.* strings are on the load path" do
    assert_equal "Dashboard", I18n.t("loam.nav.dashboard", locale: :en)
    assert_equal "Sign out", I18n.t("loam.chrome.sign_out", locale: :en)
  end

  test "an app locale file overrides the base per locale" do
    assert_equal "Pulpit", I18n.t("loam.nav.dashboard", locale: :pl)
    assert_equal "Wyloguj", I18n.t("loam.chrome.sign_out", locale: :pl)
  end
end

class LoamI18nSwitcherTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch", slug: "warsaw-i18n")
    @anna = User.create!(name: "Anna", email: "anna-i18n@example.test", password: "password")
    with_tenant(@tenant) { Loam::Membership.create!(user: @anna, role: "manager") }

    post admin_session_path, params: { email: "anna-i18n@example.test", password: "password" }
    post select_tenant_admin_session_path, params: { tenant_id: @tenant.id }
  end

  test "the locale switcher moves the admin chrome, not just the content" do
    get admin_root_path(locale: "pl")
    assert_response :success
    assert_match "Pulpit", response.body      # Dashboard, in Polish
    assert_match "Wyloguj", response.body      # Sign out

    get admin_root_path(locale: "en")
    assert_response :success
    assert_match "Dashboard", response.body
    assert_no_match(/Pulpit/, response.body)
  end

  test "a generated entity index localizes its chrome and model/field names" do
    get "/admin/equipment?locale=pl"
    assert_response :success
    assert_match "Sprzęt", response.body       # Equipment.model_name.human, Polish
    assert_match "Filtruj", response.body      # the Filter button
    assert_match "Nowy: Sprzęt", response.body # the New-record link

    get "/admin/equipment?locale=en"
    assert_response :success
    assert_match "Filter", response.body
    assert_no_match(/Filtruj/, response.body)
  end
end
