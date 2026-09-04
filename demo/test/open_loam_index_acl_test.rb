require "test_helper"

# L-711: a custom field can declare readable_roles. Filtering or sorting on a
# field the current role may not read is refused — otherwise a filter would be an
# inference oracle ("which records have clearance = top-secret?") on a value the
# role can't see. An open field (no readable_roles) is unaffected, and a
# system/background context (no actor) is trusted.
class OpenLoamIndexAclTest < ActiveSupport::TestCase
  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-acl")
    @manager = User.create!(name: "Mgr", email: "mgr-acl@example.test", password: "password")
    @clerk = User.create!(name: "Clerk", email: "clerk-acl@example.test", password: "password")
    with_tenant(@warsaw) do
      OpenLoam::Membership.create!(user: @manager, role: "manager")
      OpenLoam::Membership.create!(user: @clerk, role: "clerk")
      OpenLoam::FieldDefinition.create!(entity_type: "Equipment", name: "clearance",
                                    field_type: "string", readable_roles: [ "manager" ])
      OpenLoam::FieldDefinition.create!(entity_type: "Equipment", name: "color", field_type: "string")
    end
  end

  test "readable_by? — empty roles is open, otherwise only listed roles" do
    with_tenant(@warsaw) do
      restricted = OpenLoam::FieldDefinition.find_by!(name: "clearance")
      open_field = OpenLoam::FieldDefinition.find_by!(name: "color")

      assert restricted.readable_by?(:manager)
      refute restricted.readable_by?(:clerk)
      refute restricted.readable_by?(nil)
      assert open_field.readable_by?(:clerk)
      assert open_field.readable_by?(nil)
    end
  end

  test "a role without read on a field cannot use it as a filter oracle" do
    with_tenant(@warsaw, actor: @clerk) do
      assert_raises(OpenLoam::FieldAccessError) do
        OpenLoam::CustomFieldIndex.filter(Equipment, "clearance", "eq", "top-secret")
      end
      assert_raises(OpenLoam::FieldAccessError) do
        OpenLoam::CustomFieldIndex.order(Equipment, "clearance", :asc)
      end
    end
  end

  test "FieldAccessError is a NotAuthorizedError (renders 403 in admin)" do
    assert OpenLoam::FieldAccessError.ancestors.include?(OpenLoam::NotAuthorizedError)
  end

  test "a role with read on the field filters and sorts normally" do
    with_tenant(@warsaw, actor: @manager) do
      assert_nothing_raised do
        rel = OpenLoam::CustomFieldIndex.filter(Equipment, "clearance", "eq", "top-secret")
        assert_respond_to rel, :to_a
        OpenLoam::CustomFieldIndex.order(Equipment, "clearance", :asc).to_a
      end
    end
  end

  test "an open field (no readable_roles) is filterable by any member" do
    with_tenant(@warsaw, actor: @clerk) do
      assert_nothing_raised do
        OpenLoam::CustomFieldIndex.filter(Equipment, "color", "eq", "red").to_a
      end
    end
  end

  test "a system/background context (no actor) is not gated" do
    with_tenant(@warsaw) do
      assert_nothing_raised do
        OpenLoam::CustomFieldIndex.filter(Equipment, "clearance", "eq", "top-secret").to_a
      end
    end
  end
end
