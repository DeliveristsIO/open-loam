require "test_helper"

# Loam::Dictionaries: per-tenant managed lookup lists, usable as a custom-field
# type. Tenant-scoped, ordered, cached per request.
class LoamDictionaryTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-dict")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-dict")

    with_tenant(@warsaw) do
      dict = Loam::Dictionary.create!(key: "severity", name: "Severity")
      dict.entries.create!(value: "minor", label: "Minor", position: 1)
      dict.entries.create!(value: "critical", label: "Critical", position: 3, is_default: true)
      dict.entries.create!(value: "major", label: "Major", position: 2)
      dict.entries.create!(value: "retired", label: "Retired", position: 4, active: false)
    end
  end

  test "get / entries / default / label_for resolve for the current tenant" do
    with_tenant(@warsaw) do
      assert_equal "Severity", Loam::Dictionaries.get("severity").name
      assert_equal %w[minor major critical], Loam::Dictionaries.entries("severity").map(&:value), "ordered by position, inactive excluded"
      assert_equal "critical", Loam::Dictionaries.default("severity").value
      assert_equal "Critical", Loam::Dictionaries.label_for("severity", "critical")
    end
  end

  test "label_for returns the raw value for an unknown value or key" do
    with_tenant(@warsaw) do
      assert_equal "zzz", Loam::Dictionaries.label_for("severity", "zzz")
      assert_equal "anything", Loam::Dictionaries.label_for("no_such_dict", "anything")
    end
  end

  test "a dictionary is invisible from another tenant" do
    with_tenant(@krakow) do
      assert_nil Loam::Dictionaries.get("severity")
      assert_empty Loam::Dictionaries.entries("severity")
    end
  end

  test "an entry value is unique within its dictionary" do
    with_tenant(@warsaw) do
      dict = Loam::Dictionaries.get("severity")
      dup = dict.entries.new(value: "minor", label: "Dupe")
      refute dup.valid?
      assert dup.errors[:value].any?
    end
  end

  test "a dictionary-typed custom field round-trips a value and resolves its label" do
    with_tenant(@warsaw) do
      Loam::FieldDefinition.create!(entity_type: "DamageReport", name: "sev", field_type: "dictionary", dictionary_key: "severity")

      report = DamageReport.create!(equipment_id: 1, description: "x", state: "open")
      report.set_custom_field(:sev, "critical")
      report.save!

      assert_equal "critical", report.reload.custom_field(:sev), "stores the plain value"
      assert_equal "Critical", report.custom_field_label(:sev), "resolves the entry label"
    end
  end

  test "a dictionary field definition requires an existing dictionary" do
    with_tenant(@warsaw) do
      missing = Loam::FieldDefinition.new(entity_type: "DamageReport", name: "s2", field_type: "dictionary", dictionary_key: "nope")
      refute missing.valid?
      assert missing.errors[:dictionary_key].any?

      blank = Loam::FieldDefinition.new(entity_type: "DamageReport", name: "s3", field_type: "dictionary")
      refute blank.valid?, "a dictionary field needs a key"
    end
  end
end

# The dictionaries admin: manager-only CRUD + entry management, and a
# dictionary-typed custom field rendering a select on an entity form.
class LoamDictionaryAdminTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-dict-admin")
    @manager = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    @employee = User.create!(name: "Tomek", email: "tomek@example.test", password: "password")
    with_tenant(@tenant) do
      Loam::Membership.create!(user: @manager, role: "manager")
      Loam::Membership.create!(user: @employee, role: "employee")
    end
  end

  def sign_in(email)
    post admin_session_path, params: { email: email, password: "password" }
  end

  test "a manager creates a dictionary and adds an entry" do
    sign_in("anna@example.test")

    post admin_dictionaries_path, params: { dictionary: { key: "vehicle_category", name: "Vehicle category" } }
    dictionary = with_tenant(@tenant) { Loam::Dictionary.find_by(key: "vehicle_category") }
    assert dictionary, "the dictionary was created"

    post admin_dictionary_entries_path(dictionary), params: { dictionary_entry: { value: "van", label: "Van", position: 1 } }
    assert_equal 1, with_tenant(@tenant) { dictionary.entries.count }
    assert_equal "Van", with_tenant(@tenant) { Loam::Dictionaries.label_for("vehicle_category", "van") }
  end

  test "an employee may not manage dictionaries" do
    sign_in("tomek@example.test")
    get admin_dictionaries_path
    assert_response :forbidden
  end

  test "a dictionary-typed custom field renders a select of its entries on the entity form" do
    report = with_tenant(@tenant) do
      dict = Loam::Dictionary.create!(key: "severity", name: "Severity")
      dict.entries.create!(value: "minor", label: "Minor", position: 1)
      dict.entries.create!(value: "critical", label: "Critical", position: 2)
      Loam::FieldDefinition.create!(entity_type: "DamageReport", name: "severity", field_type: "dictionary", dictionary_key: "severity")
      DamageReport.create!(equipment_id: 1, description: "x", state: "open")
    end
    sign_in("anna@example.test")

    get edit_admin_damage_report_path(report)

    assert_response :success
    assert_select "select[name=?]", "damage_report[custom_fields][severity]" do
      assert_select "option", text: "Minor"
      assert_select "option", text: "Critical"
    end
  end
end
