require "test_helper"

# The shared comment form: one controller for every commentable entity, which
# means the entity type arrives from the browser and has to be distrusted.
class AdminCommentsTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-admin-comments")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password123")

    with_tenant(@tenant) do
      Loam::Membership.create!(user: @anna, role: "manager")
      @excavator = Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
    end

    post admin_session_path, params: { email: "anna@example.test", password: "password123" }
  end

  test "a member can comment on a record, and it shows on the record's screen" do
    post admin_comments_path, params: { commentable_type: "Equipment", commentable_id: @excavator.id,
                                        body: "Hydraulics serviced" }

    assert_response :redirect

    get admin_equipment_path(@excavator)
    assert_response :success
    assert_match(/Hydraulics serviced/, response.body)
    assert_match(/Anna/, response.body)
  end

  test "a type that is not a commentable Loam entity is refused" do
    # A real class, but not a Loam entity — the check is what the class IS,
    # not whether the name resolves.
    post admin_comments_path, params: { commentable_type: "User", commentable_id: @anna.id, body: "nope" }
    assert_response :forbidden

    post admin_comments_path, params: { commentable_type: "Loam::Tenant", commentable_id: @tenant.id, body: "nope" }
    assert_response :forbidden

    post admin_comments_path, params: { commentable_type: "Kernel", commentable_id: 1, body: "nope" }
    assert_response :forbidden

    post admin_comments_path, params: { commentable_type: "NoSuchThing", commentable_id: 1, body: "nope" }
    assert_response :forbidden

    with_tenant(@tenant) { assert_equal 0, Loam::Comment.count }
  end

  test "a record in another tenant is not found rather than commentable" do
    other_tenant = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-admin-comments")
    other_id = with_tenant(other_tenant) do
      Loam::Membership.create!(user: @anna, role: "manager")
      Equipment.create!(name: "Scaffolding", daily_rate: 80, status: "available").id
    end

    post admin_comments_path, params: { commentable_type: "Equipment", commentable_id: other_id, body: "nope" }

    assert_response :not_found, "the record simply does not exist from inside this tenant"
    with_tenant(other_tenant) { assert_equal 0, Loam::Comment.count }
  end

  test "an empty comment is reported rather than saved" do
    post admin_comments_path, params: { commentable_type: "Equipment", commentable_id: @excavator.id, body: "  " }

    assert_response :redirect
    with_tenant(@tenant) { assert_equal 0, Loam::Comment.count }

    get admin_equipment_path(@excavator)
    assert_match(/Body can&#39;t be blank/, response.body)
  end
end
