require "test_helper"

# The SSO admin screen (Admin::SsoProvidersController): manager-only per-tenant
# OIDC config, with a write-only client_secret. Covers the role gate, the
# namespaced-model form (URL/param scope), and that the secret is never rendered
# back and is only overwritten when retyped.
class AdminSsoProvidersTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-sso-admin")
    @manager = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    @employee = User.create!(name: "Tomek", email: "tomek@example.test", password: "password")
    with_tenant(@tenant) do
      OpenLoam::Membership.create!(user: @manager, role: "manager")
      OpenLoam::Membership.create!(user: @employee, role: "employee")
    end
  end

  def sign_in(email)
    post admin_session_path, params: { email: email, password: "password" }
  end

  test "a manager creates a provider through the form" do
    sign_in("anna@example.test")

    assert_difference -> { with_tenant(@tenant) { OpenLoam::SsoProvider.count } }, 1 do
      post admin_sso_providers_path, params: { sso_provider: {
        name: "Corp IdP", protocol: "oidc", issuer: "https://idp.corp.example", client_id: "cid",
        client_secret: "top-secret", domain: "Corp.Example", jit_role: "employee", active: "1",
        group_role_map: '{"admins":"manager"}'
      } }
    end

    assert_redirected_to admin_sso_providers_path
    provider = with_tenant(@tenant) { OpenLoam::SsoProvider.find_by(name: "Corp IdP") }
    assert_equal "corp.example", provider.domain, "domain is normalized"
    assert_equal({ "admins" => "manager" }, provider.group_roles)
    assert_equal "top-secret", with_tenant(@tenant) { provider.client_secret }
  end

  test "the client secret is write-only: a blank edit keeps the stored one" do
    provider = with_tenant(@tenant) do
      OpenLoam::SsoProvider.create!(name: "Corp", protocol: "oidc", client_id: "cid",
                                client_secret: "original-secret", domain: "corp.example", jit_role: "employee")
    end
    sign_in("anna@example.test")

    get edit_admin_sso_provider_path(provider)
    assert_response :success
    refute_includes response.body, "original-secret", "the secret is never rendered back"

    patch admin_sso_provider_path(provider), params: { sso_provider: {
      name: "Corp Renamed", protocol: "oidc", client_id: "cid", domain: "corp.example",
      jit_role: "employee", client_secret: "", group_role_map: "{}"
    } }
    assert_redirected_to admin_sso_providers_path

    with_tenant(@tenant) do
      provider.reload
      assert_equal "Corp Renamed", provider.name
      assert_equal "original-secret", provider.client_secret, "a blank secret field left it untouched"
    end
  end

  test "an employee may not manage SSO providers" do
    sign_in("tomek@example.test")
    get admin_sso_providers_path
    assert_response :forbidden
  end

  test "malformed group-map JSON re-renders the form as 422" do
    sign_in("anna@example.test")

    assert_no_difference -> { with_tenant(@tenant) { OpenLoam::SsoProvider.count } } do
      post admin_sso_providers_path, params: { sso_provider: {
        name: "Broken", protocol: "oidc", domain: "broken.example", jit_role: "employee",
        group_role_map: "{ not json"
      } }
    end

    assert_response :unprocessable_entity
    assert_match(/must be valid JSON/, response.body)
  end
end
