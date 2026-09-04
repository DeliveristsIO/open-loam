require "test_helper"

# The bell, end to end: the layout badge, the list, and marking one read.
# Admin screens have no other automated coverage, and a view that raises would
# otherwise only be found by opening a browser.
class AdminNotificationsTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-admin-notify")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    @tomek = User.create!(name: "Tomek", email: "tomek@example.test", password: "password")

    with_tenant(@tenant) do
      OpenLoam::Membership.create!(user: @anna, role: "manager")
      OpenLoam::Membership.create!(user: @tomek, role: "employee")
      @notification = OpenLoam::Notifications.notify(@anna, title: "Approval needed", body: "Damage report").first
      OpenLoam::Notifications.notify(@tomek, title: "Not for Anna")
    end

    # Anna belongs to this tenant only, so signing in selects it for her.
    post admin_session_path, params: { email: "anna@example.test", password: "password" }
  end

  test "the layout shows the unread count and the index lists only your own notifications" do
    get admin_notifications_path

    assert_response :success
    assert_select "nav a", text: "Notifications (1)"
    assert_select "td", text: /Approval needed/
    assert_no_match(/Not for Anna/, response.body, "Tomek's notification must not appear in Anna's list")
  end

  test "marking a notification read clears it from the badge" do
    post mark_read_admin_notification_path(@notification)

    assert_redirected_to admin_notifications_path
    with_tenant(@tenant) { assert OpenLoam::Notification.find(@notification.id).read? }

    follow_redirect!
    assert_select "nav a", text: "Notifications (0)"
  end
end
