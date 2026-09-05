require "test_helper"

# API tokens are bearer credentials: the row stores only a SHA-256 digest, and a
# token stops working the moment its user loses the membership that justified it.
class OpenLoamApiTokenTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-token")
    @anna = User.create!(name: "Anna", email: "anna@token.test", password: "password123")
    with_tenant(@tenant) do
      OpenLoam::Membership.create!(user: @anna, role: "manager")
      @token = OpenLoam::ApiToken.create!(user: @anna, label: "ops")
    end
    @raw = @token.token
  end

  test "the raw column holds no usable credential" do
    stored = OpenLoam::ApiToken.connection.select_value(
      "SELECT token_digest FROM open_loam_api_tokens WHERE id = #{@token.id}"
    )

    assert_not_equal @raw, stored
    assert_equal OpenLoam::ApiToken.digest(@raw), stored
    assert_not_includes OpenLoam::ApiToken.column_names, "token", "the plaintext column is gone"
  end

  test "the plaintext is unrecoverable once the instance is gone" do
    assert_nil with_tenant(@tenant) { OpenLoam::ApiToken.find(@token.id).token }
  end

  test "the token still authenticates" do
    get "/api/equipment", headers: { "Authorization" => "Bearer #{@raw}" }

    assert_response :success
  end

  test "a stolen digest is not a usable bearer token" do
    get "/api/equipment", headers: { "Authorization" => "Bearer #{OpenLoam::ApiToken.digest(@raw)}" }

    assert_response :unauthorized
  end

  # A token outlives the membership unless something checks — offboarding
  # someone from a tenant has to end their machine access to it too.
  test "revoking the membership stops the token working" do
    with_tenant(@tenant) { OpenLoam::Membership.find_by(user_id: @anna.id).destroy! }

    get "/api/equipment", headers: { "Authorization" => "Bearer #{@raw}" }

    assert_response :unauthorized
    assert_nil OpenLoam::Current.tenant, "and no context was left established"
  end

  test "a manager can revoke another member's token; an employee cannot" do
    tomek = User.create!(name: "Tomek", email: "tomek@token.test", password: "password123")
    with_tenant(@tenant) { OpenLoam::Membership.create!(user: tomek, role: "employee") }

    post admin_session_path, params: { email: "tomek@token.test", password: "password123" }
    delete admin_api_token_path(@token)
    assert with_tenant(@tenant) { OpenLoam::ApiToken.exists?(@token.id) }, "an employee may not revoke Anna's token"

    post admin_session_path, params: { email: "anna@token.test", password: "password123" }
    tomeks = with_tenant(@tenant) { OpenLoam::ApiToken.create!(user: tomek, label: "scanner") }
    delete admin_api_token_path(tomeks)

    assert_not with_tenant(@tenant) { OpenLoam::ApiToken.exists?(tomeks.id) }, "a manager owns offboarding"
  end

  test "a token from another tenant is not findable, let alone revocable" do
    krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-token")
    stranger = User.create!(name: "Stranger", email: "stranger@token.test", password: "password123")
    elsewhere = with_tenant(krakow) do
      OpenLoam::Membership.create!(user: stranger, role: "manager")
      OpenLoam::ApiToken.create!(user: stranger, label: "theirs")
    end

    post admin_session_path, params: { email: "anna@token.test", password: "password123" }
    delete admin_api_token_path(elsewhere)

    assert with_tenant(krakow) { OpenLoam::ApiToken.exists?(elsewhere.id) }
  end
end
