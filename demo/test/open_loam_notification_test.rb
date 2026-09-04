require "test_helper"

# In-app notifications: created through OpenLoam::Notifications, scoped to the
# tenant they were sent in, and delivered to one recipient each.
class OpenLoamNotificationTest < ActiveSupport::TestCase
  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-notify")
    @krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-notify")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    @bogdan = User.create!(name: "Bogdan", email: "bogdan@example.test", password: "password")
    @tomek = User.create!(name: "Tomek", email: "tomek@example.test", password: "password")

    with_tenant(@warsaw) do
      OpenLoam::Membership.create!(user: @anna, role: "manager")
      OpenLoam::Membership.create!(user: @bogdan, role: "manager")
      OpenLoam::Membership.create!(user: @tomek, role: "employee")
    end

    with_tenant(@krakow) { OpenLoam::Membership.create!(user: @anna, role: "manager") }
  end

  test "notify creates a record in the current tenant for each recipient" do
    with_tenant(@warsaw) do
      notifications = OpenLoam::Notifications.notify([ @anna, @tomek ], title: "Depot closing early")

      assert_equal 2, notifications.size
      assert_equal [ @warsaw.id ], notifications.map(&:tenant_id).uniq
      assert_equal [ @anna.id, @tomek.id ], notifications.map(&:user_id)
      assert_equal 2, OpenLoam::Notification.count
    end
  end

  test "notify records what the message is about" do
    with_tenant(@warsaw, actor: @anna) do
      report = DamageReport.create!(equipment_id: 1, description: "Cracked casing")
      notification = OpenLoam::Notifications.notify(@anna, title: "Report filed", body: "Have a look", source: report).first

      assert_equal "Have a look", notification.body
      assert_equal "DamageReport", notification.source_type
      assert_equal report.id, notification.source_id
    end
  end

  test "a notification is unread until it is marked read" do
    with_tenant(@warsaw) do
      notification = OpenLoam::Notifications.notify(@anna, title: "Depot closing early").first

      refute notification.read?
      assert_equal [ notification ], OpenLoam::Notification.unread.to_a

      notification.mark_read!

      assert notification.read?
      assert_empty OpenLoam::Notification.unread
    end
  end

  test "notify_role reaches every holder of that role in the current tenant, and nobody else" do
    with_tenant(@warsaw) do
      notifications = OpenLoam::Notifications.notify_role(:manager, title: "Approval needed")

      assert_equal [ @anna.id, @bogdan.id ].sort, notifications.map(&:user_id).sort,
                   "both Warsaw managers, and not the employee"
    end

    # Anna is a manager in Krakow too, but the Warsaw send must not have
    # reached her Krakow inbox.
    with_tenant(@krakow) { assert_equal 0, OpenLoam::Notification.count }
  end

  test "notifications are invisible outside the tenant they were sent in" do
    id = with_tenant(@warsaw) { OpenLoam::Notifications.notify(@anna, title: "Depot closing early").first.id }

    with_tenant(@krakow) do
      assert_equal 0, OpenLoam::Notification.count
      assert_raises(ActiveRecord::RecordNotFound) { OpenLoam::Notification.find(id) }
    end
  end

  test "touching notifications with no tenant context raises" do
    assert_raises(OpenLoam::MissingTenantError) { OpenLoam::Notification.count }
  end

  test "approving a damage report notifies the branch's managers" do
    with_tenant(@warsaw, actor: @tomek) do
      report = DamageReport.create!(equipment_id: 1, description: "Cracked casing")
      report.submit!
    end

    with_tenant(@warsaw, actor: @anna) do
      DamageReport.first.approve!

      notifications = OpenLoam::Notification.all
      assert_equal [ @anna.id, @bogdan.id ].sort, notifications.map(&:user_id).sort
      assert_match(/approved/, notifications.first.title)
      assert_equal "DamageReport", notifications.first.source_type
      assert_match(/pending_approval to approved/, notifications.first.body)
    end

    with_tenant(@krakow) { assert_equal 0, OpenLoam::Notification.count, "Krakow's manager is not involved" }
  end
end
