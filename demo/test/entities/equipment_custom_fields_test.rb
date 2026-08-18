require "test_helper"

# Proves the migration-free custom-fields loop end to end: a Loam::FieldDefinition
# drives typed read/write on Equipment with no column and no migration, an
# undeclared key fails loudly, and definitions (like everything else in Loam)
# are tenant-isolated.
class EquipmentCustomFieldsTest < ActiveSupport::TestCase
  setup do
    @tenant_a = Loam::Tenant.create!(name: "Tenant A", slug: "a-equipment-cf")
    @tenant_b = Loam::Tenant.create!(name: "Tenant B", slug: "b-equipment-cf")
    @manager = User.create!(name: "Manager")
  end

  test "a defined field round-trips through set_custom_field/custom_field with type casting" do
    with_tenant(@tenant_a, actor: @manager) do
      Loam::FieldDefinition.create!(entity_type: "Equipment", name: "serial_number", field_type: "string")
      Loam::FieldDefinition.create!(entity_type: "Equipment", name: "warranty_expires_at", field_type: "date")

      equipment = Equipment.create!(name: "Drill", daily_rate: 10, status: "available")
      equipment.set_custom_field(:serial_number, "SN-1")
      equipment.set_custom_field(:warranty_expires_at, Date.new(2027, 1, 1))
      equipment.save!

      reloaded = Equipment.find(equipment.id)
      assert_equal "SN-1", reloaded.custom_field(:serial_number)
      assert_equal Date.new(2027, 1, 1), reloaded.custom_field(:warranty_expires_at)
    end
  end

  test "reading or writing an undeclared custom field raises Loam::UnknownCustomFieldError" do
    with_tenant(@tenant_a, actor: @manager) do
      equipment = Equipment.create!(name: "Drill", daily_rate: 10, status: "available")

      assert_raises(Loam::UnknownCustomFieldError) { equipment.custom_field(:not_defined) }
      assert_raises(Loam::UnknownCustomFieldError) { equipment.set_custom_field(:not_defined, "x") }
    end
  end

  test "field definitions are tenant-isolated" do
    with_tenant(@tenant_a) do
      Loam::FieldDefinition.create!(entity_type: "Equipment", name: "serial_number", field_type: "string")
    end

    with_tenant(@tenant_b, actor: @manager) do
      equipment = Equipment.create!(name: "Drill", daily_rate: 10, status: "available")
      assert_raises(Loam::UnknownCustomFieldError) { equipment.custom_field(:serial_number) }
    end
  end
end
