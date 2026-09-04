require "test_helper"

# Admin authentication: email + password, then a tenant the user actually
# belongs to. The second half is the part that matters for a multi-tenant app —
# signing in proves who you are, not where you may go.
class AdminAuthTest < ActionDispatch::IntegrationTest
  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-auth")
    @krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-auth")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password123")
    @tomek = User.create!(name: "Tomek", email: "tomek@example.test", password: "password123")

    # Anna is in both branches, Tomek in Warsaw only.
    with_tenant(@warsaw) do
      OpenLoam::Membership.create!(user: @anna, role: "manager")
      OpenLoam::Membership.create!(user: @tomek, role: "employee")
    end
    with_tenant(@krakow) { OpenLoam::Membership.create!(user: @anna, role: "manager") }
  end

  test "an unauthenticated request to an admin screen is sent to the sign-in page" do
    get admin_equipment_index_path

    assert_redirected_to new_admin_session_path
  end

  test "the wrong password is refused without saying which half was wrong" do
    post admin_session_path, params: { email: "tomek@example.test", password: "wrong" }

    assert_response :unauthorized
    assert_match(/Wrong email or password/, response.body)
    refute_match(/no account|unknown user/i, response.body)
    assert_nil session[:user_id]
  end

  test "an unknown email is refused the same way" do
    post admin_session_path, params: { email: "nobody@example.test", password: "password123" }

    assert_response :unauthorized
    assert_match(/Wrong email or password/, response.body)
  end

  test "email is matched however it was typed" do
    post admin_session_path, params: { email: "  ToMeK@Example.TEST ", password: "password123" }

    assert_redirected_to admin_root_path
  end

  test "a user who belongs to exactly one tenant lands straight on the dashboard" do
    post admin_session_path, params: { email: "tomek@example.test", password: "password123" }

    assert_redirected_to admin_root_path
    assert_equal @warsaw.id, session[:tenant_id]

    follow_redirect!
    assert_response :success
    assert_select "strong", text: "Branch Warsaw"
  end

  test "a user in several tenants picks one, and only from their own" do
    post admin_session_path, params: { email: "anna@example.test", password: "password123" }

    assert_redirected_to new_admin_session_path
    assert_nil session[:tenant_id], "no tenant is chosen until Anna picks one"

    follow_redirect!
    assert_select "h1", text: "Choose a tenant"
    assert_select "option", text: "Branch Warsaw"
    assert_select "option", text: "Branch Krakow"

    post select_tenant_admin_session_path, params: { tenant_id: @krakow.id }
    assert_redirected_to admin_root_path
    assert_equal @krakow.id, session[:tenant_id]
  end

  test "a tenant the user has no membership in cannot be entered" do
    outsider_tenant = OpenLoam::Tenant.create!(name: "Branch Gdansk", slug: "gdansk-auth")

    post admin_session_path, params: { email: "anna@example.test", password: "password123" }
    post select_tenant_admin_session_path, params: { tenant_id: outsider_tenant.id }

    assert_redirected_to new_admin_session_path
    assert_nil session[:tenant_id]
  end

  test "a session whose membership was revoked stops working immediately" do
    post admin_session_path, params: { email: "tomek@example.test", password: "password123" }
    get admin_root_path
    assert_response :success

    with_tenant(@warsaw) { OpenLoam::Membership.find_by(user_id: @tomek.id).destroy! }

    get admin_root_path
    assert_redirected_to new_admin_session_path
  end

  test "signing out clears the session" do
    post admin_session_path, params: { email: "tomek@example.test", password: "password123" }
    delete admin_session_path

    assert_redirected_to new_admin_session_path
    assert_nil session[:user_id]
    assert_nil session[:tenant_id]

    get admin_root_path
    assert_redirected_to new_admin_session_path
  end

  test "a user can mint and revoke their own API token" do
    post admin_session_path, params: { email: "tomek@example.test", password: "password123" }

    post admin_api_tokens_path, params: { label: "nightly export" }
    follow_redirect!

    assert_response :success
    token = with_tenant(@warsaw) { OpenLoam::ApiToken.find_by(user_id: @tomek.id) }
    assert token, "the token belongs to the signed-in user in the current tenant"
    assert_match token.token, response.body, "the value is shown once, on the screen after creation"

    delete admin_api_token_path(token)
    assert with_tenant(@warsaw) { OpenLoam::ApiToken.where(user_id: @tomek.id).empty? }
  end
end
