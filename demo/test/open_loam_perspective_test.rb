require "test_helper"

# Loam::Perspectives: saved views of an entity index, with private / role /
# tenant visibility, a resolved default, and filter/sort application that only
# ever touches whitelisted columns.
class LoamPerspectiveTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-psp")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-psp")
    @manager = User.create!(name: "Manager", email: "mgr@example.test", password: "password")
    @employee = User.create!(name: "Employee", email: "emp@example.test", password: "password")

    with_tenant(@warsaw) do
      Loam::Membership.create!(user: @manager, role: "manager")
      Loam::Membership.create!(user: @employee, role: "employee")
    end
  end

  test "a private view is visible only to its owner" do
    with_tenant(@warsaw) do
      Loam::Perspective.create!(entity_type: "Equipment", name: "Mine", owner_id: @manager.id, visibility: "private")

      assert_equal [ "Mine" ], names(Loam::Perspectives.visible_to("Equipment", user: @manager))
      assert_empty names(Loam::Perspectives.visible_to("Equipment", user: @employee)), "another user cannot see it"
    end
  end

  test "a role-shared view is visible only to that role; a tenant view to everyone" do
    with_tenant(@warsaw) do
      Loam::Perspective.create!(entity_type: "Equipment", name: "Managers", visibility: "role", role: "manager")
      Loam::Perspective.create!(entity_type: "Equipment", name: "Everyone", visibility: "tenant")

      assert_equal %w[Everyone Managers], names(Loam::Perspectives.visible_to("Equipment", user: @manager)).sort
      assert_equal [ "Everyone" ], names(Loam::Perspectives.visible_to("Equipment", user: @employee))
    end
  end

  test "default_for resolves most specific audience first: private > role > tenant" do
    with_tenant(@warsaw) do
      Loam::Perspective.create!(entity_type: "Equipment", name: "T", visibility: "tenant", is_default: true)
      Loam::Perspective.create!(entity_type: "Equipment", name: "R", visibility: "role", role: "manager", is_default: true)
      Loam::Perspective.create!(entity_type: "Equipment", name: "P", owner_id: @manager.id, visibility: "private", is_default: true)

      assert_equal "P", Loam::Perspectives.default_for("Equipment", user: @manager).name, "the manager's own default wins"
      # The employee is not the manager role and owns nothing, so the role and
      # private defaults are invisible — they fall back to the tenant default.
      assert_equal "T", Loam::Perspectives.default_for("Equipment", user: @employee).name
    end
  end

  test "make_default unsets the sibling default in the same audience" do
    with_tenant(@warsaw) do
      first = Loam::Perspective.create!(entity_type: "Equipment", name: "A", visibility: "tenant", is_default: true)
      second = Loam::Perspective.create!(entity_type: "Equipment", name: "B", visibility: "tenant")

      second.make_default!

      refute first.reload.is_default?, "the previous tenant default is unset"
      assert second.reload.is_default?
    end
  end

  test "apply filters and sorts, and ignores any key that is not a real data column" do
    with_tenant(@warsaw) do
      cheap = Equipment.create!(name: "Cheap", daily_rate: 50, status: "available")
      Equipment.create!(name: "Pricey", daily_rate: 900, status: "rented")

      perspective = Loam::Perspective.new(
        entity_type: "Equipment", name: "v", visibility: "tenant",
        config: {
          "filters" => { "status" => "available", "tenant_id" => @krakow.id, "1=1; DROP TABLE" => "x" },
          "sort" => { "field" => "daily_rate", "dir" => "asc" }
        }
      )

      result = perspective.apply(Equipment.all)
      assert_equal [ cheap.id ], result.pluck(:id), "only the status filter applied; tenant_id and the garbage key were ignored"
    end
  end

  test "a crafted sort on a plumbing column is ignored" do
    with_tenant(@warsaw) do
      Equipment.create!(name: "A", daily_rate: 1, status: "available")
      perspective = Loam::Perspective.new(entity_type: "Equipment", name: "v", visibility: "tenant",
                                          config: { "sort" => { "field" => "tenant_id", "dir" => "asc" } })

      assert_nothing_raised { perspective.apply(Equipment.all).to_a }
    end
  end

  test "resolve('none') shows everything, bypassing the tenant default" do
    with_tenant(@warsaw) do
      Loam::Perspective.create!(entity_type: "Equipment", name: "Default", visibility: "tenant", is_default: true)

      assert Loam::Perspectives.resolve("Equipment", user: @manager), "a default resolves by default"
      assert_nil Loam::Perspectives.resolve("Equipment", user: @manager, id: "none"), "'none' escapes the default"
    end
  end

  test "perspectives are tenant-isolated" do
    with_tenant(@warsaw) { Loam::Perspective.create!(entity_type: "Equipment", name: "W", visibility: "tenant") }

    with_tenant(@krakow) do
      assert_empty names(Loam::Perspectives.visible_to("Equipment", user: @manager)), "Warsaw's view is invisible from Krakow"
    end
  end

  private

  def names(relation)
    relation.map(&:name)
  end
end

# The admin management screen and the "save current view" flow.
class AdminPerspectivesFlowTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-psp-flow")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    @tomek = User.create!(name: "Tomek", email: "tomek@example.test", password: "password")

    with_tenant(@tenant) do
      Loam::Membership.create!(user: @anna, role: "manager")
      Loam::Membership.create!(user: @tomek, role: "employee")
    end
  end

  test "saving the current view creates a private view owned by the actor" do
    sign_in(@tomek)

    post admin_perspectives_path, params: { entity_type: "Equipment", name: "Tomek's view", q: "cat" }
    assert_response :redirect

    with_tenant(@tenant) do
      view = Loam::Perspective.find_by(name: "Tomek's view")
      assert view
      assert_equal "private", view.visibility
      assert_equal @tomek.id, view.owner_id
      assert_equal({ "q" => "cat" }, view.config["filters"])
    end
  end

  test "an owner edits their own private view but an employee cannot widen it to the tenant" do
    view = with_tenant(@tenant) do
      Loam::Perspective.create!(entity_type: "Equipment", name: "Tomek's", owner_id: @tomek.id, visibility: "private")
    end
    sign_in(@tomek)

    # Renaming your own private view is fine.
    patch admin_perspective_path(view, entity_type: "Equipment"), params: { perspective: { name: "Renamed" } }
    assert_response :redirect
    assert_equal "Renamed", view.reload.name

    # Publishing it to the whole tenant is a manager action — the escalation path.
    patch admin_perspective_path(view, entity_type: "Equipment"), params: { perspective: { visibility: "tenant" } }
    assert_response :forbidden
    assert_equal "private", view.reload.visibility
  end

  test "a manager may widen their own private view to the tenant" do
    view = with_tenant(@tenant) do
      Loam::Perspective.create!(entity_type: "Equipment", name: "Anna's", owner_id: @anna.id, visibility: "private")
    end
    sign_in(@anna)

    patch admin_perspective_path(view, entity_type: "Equipment"), params: { perspective: { visibility: "tenant" } }
    assert_response :redirect
    assert_equal "tenant", view.reload.visibility
  end

  test "only a manager may widen a shared view; an employee is refused" do
    view = with_tenant(@tenant) do
      Loam::Perspective.create!(entity_type: "Equipment", name: "Team", visibility: "tenant", owner_id: @anna.id)
    end

    sign_in(@tomek) # employee, not the owner
    patch admin_perspective_path(view, entity_type: "Equipment"), params: { perspective: { name: "Hacked" } }
    assert_response :forbidden
    assert_equal "Team", view.reload.name

    sign_in(@anna) # manager
    patch admin_perspective_path(view, entity_type: "Equipment"), params: { perspective: { name: "Team renamed" } }
    assert_response :redirect
    assert_equal "Team renamed", view.reload.name
  end

  private

  def sign_in(user)
    post admin_session_path, params: { email: user.email, password: "password" }
  end
end
