require "test_helper"

# Regression: the admin form nests custom-field inputs under the model's param
# key (equipment[custom_fields][serial_number]), and assign_custom_fields! must
# read them from there. A top-level params[:custom_fields] read saved nothing
# while redirecting as if it had — found by an agent during the first
# golden-tasks benchmark run.
class AdminCustomFieldsTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-custom-fields")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")

    with_tenant(@tenant) do
      Loam::Membership.create!(user: @anna, role: "manager")
      Loam::FieldDefinition.create!(entity_type: "Equipment", name: "serial_number", field_type: "string")
      @excavator = Equipment.create!(name: "Excavator", daily_rate: 500.0, status: "available")
    end

    post admin_session_path, params: { email: "anna@example.test", password: "password" }
  end

  test "a custom field submitted through the nested admin form params is persisted" do
    patch polymorphic_path([:admin, @excavator]), params: {
      equipment: {
        name: "Excavator",
        custom_fields: { serial_number: "SN-001" }
      }
    }

    assert_response :redirect
    with_tenant(@tenant) do
      assert_equal "SN-001", Equipment.find(@excavator.id).custom_field(:serial_number),
        "the nested custom_fields params were not persisted"
    end
  end

  test "the persisted custom field renders back on the show screen" do
    with_tenant(@tenant) do
      @excavator.set_custom_field(:serial_number, "SN-002")
      @excavator.save!
    end

    get polymorphic_path([:admin, @excavator])

    assert_response :success
    assert_match "SN-002", response.body
  end
end
