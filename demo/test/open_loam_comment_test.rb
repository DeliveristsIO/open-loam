require "test_helper"

# Comments: a discussion on any OpenLoam entity, tenant-scoped like its subject.
class OpenLoamCommentTest < ActiveSupport::TestCase
  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-comments")
    @krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-comments")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")

    with_tenant(@warsaw) do
      OpenLoam::Membership.create!(user: @anna, role: "manager")
      @excavator = Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
    end
  end

  test "comment! records the body, the author and the tenant" do
    with_tenant(@warsaw, actor: @anna) do
      comment = @excavator.comment!("Hydraulics serviced")

      assert_equal "Hydraulics serviced", comment.body
      assert_equal @anna.id, comment.author_id
      assert_equal @warsaw.id, comment.tenant_id
      assert_equal [ comment ], @excavator.open_loam_comments.to_a
    end
  end

  test "a comment publishes open_loam.comment.created so notifications and webhooks can react" do
    received = []
    subscription = OpenLoam::Events.subscribe("open_loam.comment.created") { |_name, payload| received << payload }

    with_tenant(@warsaw, actor: @anna) { @excavator.comment!("Hydraulics serviced") }

    assert_equal 1, received.size
    assert_equal @warsaw.id, received.first[:tenant_id]
    assert_equal @anna.id, received.first[:actor_id]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  test "an empty comment is refused" do
    with_tenant(@warsaw, actor: @anna) do
      assert_raises(ActiveRecord::RecordInvalid) { @excavator.comment!("") }
    end
  end

  test "comments are ordered oldest first, the way a conversation reads" do
    with_tenant(@warsaw, actor: @anna) do
      @excavator.comment!("First")
      @excavator.comment!("Second")

      assert_equal %w[First Second], @excavator.open_loam_comments.oldest_first.pluck(:body)
    end
  end

  test "comments are invisible from another tenant" do
    with_tenant(@warsaw, actor: @anna) { @excavator.comment!("Hydraulics serviced") }

    with_tenant(@krakow) { assert_equal 0, OpenLoam::Comment.count }
  end

  test "destroying the record destroys its comments" do
    with_tenant(@warsaw, actor: @anna) do
      @excavator.comment!("Hydraulics serviced")
      assert_equal 1, OpenLoam::Comment.count

      @excavator.destroy!

      assert_equal 0, OpenLoam::Comment.count
    end
  end
end
