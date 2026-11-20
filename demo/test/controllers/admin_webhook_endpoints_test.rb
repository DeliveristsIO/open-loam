require "test_helper"

# The signing secret is shown exactly once: on the page create renders.
class AdminWebhookEndpointsTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = OpenLoam::Tenant.create!(name: "Branch Wroclaw", slug: "wroclaw-admin-webhooks")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password123")
    with_tenant(@tenant) { OpenLoam::Membership.create!(user: @anna, role: "manager") }

    post admin_session_path, params: { email: "anna@example.test", password: "password123" }
  end

  test "create shows the new secret once, uncached, and the list does not" do
    post admin_webhook_endpoints_path, params: { webhook_endpoint: { url: "https://example.test/hook",
                                                                      event_pattern: "rental.", active: "1" } }

    assert_response :created
    assert_equal "no-store", response.headers["Cache-Control"]
    secret = with_tenant(@tenant) { OpenLoam::WebhookEndpoint.last.secret }
    assert_includes response.body, secret
    assert_includes response.body, admin_webhook_endpoints_path

    get admin_webhook_endpoints_path
    assert_response :success
    refute_includes response.body, secret
  end

  test "the new page says the secret is shown once after saving" do
    get new_admin_webhook_endpoint_path
    assert_response :success
    assert_match(/shown once after you save/, response.body)
  end
end
