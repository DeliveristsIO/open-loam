require "test_helper"

# Field-level READ enforcement. `field readable:` and a FieldDefinition's
# readable_roles were declared but only ever consulted by the CSV export's column
# list and the custom-field filter index — the JSON API, the admin screens and
# the export's custom-field columns all served restricted values to any member.
#
# EquipmentPolicy declares `field :daily_rate, readable: [:manager]`, so an
# employee is the negative case throughout.
class OpenLoamReadAclTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-readacl")
    @manager = User.create!(name: "Marta", email: "marta@readacl.test", password: "password123")
    @employee = User.create!(name: "Ewa", email: "ewa@readacl.test", password: "password123")

    with_tenant(@tenant) do
      OpenLoam::Membership.create!(user: @manager, role: "manager")
      OpenLoam::Membership.create!(user: @employee, role: "employee")
      OpenLoam::Current.actor = @manager
      @excavator = Equipment.create!(name: "Excavator", daily_rate: 999.99, status: "available")
      OpenLoam::Current.actor = nil
    end
  end

  def token_for(user)
    with_tenant(@tenant) { OpenLoam::ApiToken.create!(user_id: user.id, label: "readacl").token }
  end

  def api_get(path, user)
    get path, headers: { "Authorization" => "Bearer #{token_for(user)}" }
    JSON.parse(response.body)
  end

  def sign_in(user)
    post admin_session_path, params: { email: user.email, password: "password123" }
  end

  # --- JSON API -------------------------------------------------------------

  test "the JSON show withholds a field the role may not read" do
    body = api_get("/api/equipment/#{@excavator.id}", @employee)

    assert_equal "Excavator", body["name"], "readable fields still come through"
    assert_not body.key?("daily_rate"), "daily_rate is manager-only"
    assert_not response.body.include?("999.99"), "and its value is nowhere in the payload"
  end

  test "the JSON show serves the field to a role that may read it" do
    body = api_get("/api/equipment/#{@excavator.id}", @manager)

    assert_equal "999.99", body["daily_rate"].to_s
  end

  test "the JSON index withholds it too" do
    body = api_get("/api/equipment", @employee)

    assert_not body.first.key?("daily_rate")
  end

  # --- Admin screens --------------------------------------------------------

  test "the admin show screen omits a field the role may not read" do
    sign_in(@employee)
    get admin_equipment_path(@excavator)

    assert_response :success
    assert_match "Excavator", response.body
    assert_no_match(/999\.99/, response.body)
  end

  test "the admin index omits the column entirely, header and cells" do
    sign_in(@employee)
    get admin_equipment_index_path

    assert_response :success
    assert_no_match(/999\.99/, response.body)
    assert_no_match(/Daily rate/i, response.body, "no column header either")
  end

  test "the edit form does not print an unreadable field as read-only text" do
    sign_in(@employee)
    get edit_admin_equipment_path(@excavator)

    assert_response :success
    assert_no_match(/999\.99/, response.body)
  end

  test "a manager still sees all of it" do
    sign_in(@manager)
    get admin_equipment_path(@excavator)

    assert_match(/999\.99/, response.body)
  end

  # --- Sort as an inference oracle -----------------------------------------

  test "sorting by an unreadable column is ignored, not honoured" do
    with_tenant(@tenant) do
      OpenLoam::Current.actor = @manager
      Equipment.create!(name: "Cheap", daily_rate: 1, status: "available")
      OpenLoam::Current.actor = nil
    end
    sign_in(@employee)

    get admin_equipment_index_path(sort: "daily_rate", dir: "asc")

    assert_response :success
    # Ordering by a hidden column would let an employee rank records by a value
    # they cannot see. The default order (newest first) stands instead.
    assert_operator response.body.index("Cheap"), :<, response.body.index("Excavator")
  end

  # --- Custom fields --------------------------------------------------------

  test "a restricted custom field is withheld from the API, the screen and the CSV" do
    with_tenant(@tenant) do
      OpenLoam::FieldDefinition.create!(entity_type: "Equipment", name: "purchase_price",
                                        field_type: "string", readable_roles: [ "manager" ])
      OpenLoam::Current.actor = @manager
      @excavator.set_custom_field("purchase_price", "480000")
      @excavator.save!
      OpenLoam::Current.actor = nil
    end

    body = api_get("/api/equipment/#{@excavator.id}", @employee)
    assert_not body["custom_fields"].key?("purchase_price"), "not in the JSON"
    assert_not response.body.include?("480000")

    sign_in(@employee)
    get admin_equipment_path(@excavator)
    assert_no_match(/480000/, response.body, "not on the admin screen")

    columns = with_tenant(@tenant) { OpenLoam::Export.exportable_columns(Equipment, @employee) }
    assert_not_includes columns.map { |c| c[:header] }, "purchase_price", "not a CSV column"
  end

  test "a manager gets the restricted custom field in all three" do
    with_tenant(@tenant) do
      OpenLoam::FieldDefinition.create!(entity_type: "Equipment", name: "purchase_price",
                                        field_type: "string", readable_roles: [ "manager" ])
      OpenLoam::Current.actor = @manager
      @excavator.set_custom_field("purchase_price", "480000")
      @excavator.save!
      OpenLoam::Current.actor = nil
    end

    body = api_get("/api/equipment/#{@excavator.id}", @manager)
    assert_equal "480000", body["custom_fields"]["purchase_price"]

    columns = with_tenant(@tenant) { OpenLoam::Export.exportable_columns(Equipment, @manager) }
    assert_includes columns.map { |c| c[:header] }, "purchase_price"
  end

  # --- Derived read paths ---------------------------------------------------

  test "the history screen does not replay a restricted field as an old to new pair" do
    with_tenant(@tenant) do
      OpenLoam::Current.actor = @manager
      @excavator.update!(daily_rate: 777.77)
      OpenLoam::Current.actor = nil
    end
    sign_in(@employee)

    get admin_history_path(type: "Equipment", record_id: @excavator.id)

    assert_response :success
    assert_no_match(/777\.77/, response.body)
    assert_no_match(/999\.99/, response.body, "neither side of the pair")
  end

  test "the history screen filters restricted runtime fields out of the custom_fields blob" do
    with_tenant(@tenant) do
      OpenLoam::FieldDefinition.create!(entity_type: "Equipment", name: "secret_note",
                                        field_type: "string", readable_roles: [ "manager" ])
      OpenLoam::FieldDefinition.create!(entity_type: "Equipment", name: "public_note", field_type: "string")
      OpenLoam::Current.actor = @manager
      @excavator.set_custom_field("secret_note", "CLASSIFIED")
      @excavator.set_custom_field("public_note", "ROUTINE")
      @excavator.save!
      OpenLoam::Current.actor = nil
    end
    sign_in(@employee)

    get admin_history_path(type: "Equipment", record_id: @excavator.id)

    assert_no_match(/CLASSIFIED/, response.body)
    assert_match(/ROUTINE/, response.body, "the readable one still shows")
  end

  test "an edit conflict does not diff a field the role may not read" do
    sign_in(@employee)
    get edit_admin_equipment_path(@excavator)

    # Someone else saves first, so the employee's submit carries a stale lock_version.
    with_tenant(@tenant) do
      OpenLoam::Current.actor = @manager
      @excavator.update!(daily_rate: 555.55)
      OpenLoam::Current.actor = nil
    end

    patch admin_equipment_path(@excavator),
          params: { equipment: { name: "Renamed", lock_version: 0 } }

    assert_response :conflict
    assert_no_match(/555\.55/, response.body, "the conflict table is a read path too")
  end

  # --- Fail closed ----------------------------------------------------------

  test "a model with no policy class raises instead of falling back to the base policy" do
    # OpenLoam::Policy answers "any member" to every check, so falling back to it
    # would silently grant everything an explicit policy exists to restrict.
    error = assert_raises(OpenLoam::Error) do
      OpenLoam::Policy.for_model(OpenLoam::Tenant, @employee)
    end
    assert_match(/No policy defined for OpenLoam::Tenant/, error.message)
  end
end

# Staging is deliberately ungated ("propose" is not "apply"), so approval is
# where authority is spent — and it used to spend it on an unfiltered changeset
# applied to a bare constantize of a stored string.
class OpenLoamStagedChangeTest < ActiveSupport::TestCase
  setup do
    @tenant = OpenLoam::Tenant.create!(name: "T", slug: "staged-change")
    @manager = User.create!(name: "M", email: "m@staged.test", password: "password123")
    @employee = User.create!(name: "E", email: "e@staged.test", password: "password123")
    with_tenant(@tenant) do
      OpenLoam::Membership.create!(user: @manager, role: "manager")
      OpenLoam::Membership.create!(user: @employee, role: "employee")
      OpenLoam::Current.actor = @manager
      @excavator = Equipment.create!(name: "Excavator", daily_rate: 100, status: "available")
      OpenLoam::Current.actor = nil
    end
  end

  def stage(changes, actor:, target: @excavator, target_type: nil)
    with_tenant(@tenant) do
      OpenLoam::Current.actor = actor
      action = OpenLoam::PendingActions.stage(summary: "s", on: target, action: :update, changes: changes)
      action.update_column(:target_type, target_type) if target_type
      OpenLoam::Current.actor = nil
      action
    end
  end

  test "a non-tenant-scoped target is refused, not constantized and written" do
    action = stage({ name: "x" }, actor: @employee, target_type: "User")

    with_tenant(@tenant) do
      OpenLoam::Current.actor = @manager
      action.approve!(by: @manager)
      OpenLoam::Current.actor = nil
    end

    assert_equal "failed", action.reload.status
    assert_match(/not a tenant-scoped model/, action.error)
  end

  test "a staged change may not carry soft-delete or tenancy plumbing" do
    action = stage({ "deleted_at" => Time.current }, actor: @employee)

    with_tenant(@tenant) do
      OpenLoam::Current.actor = @manager
      action.approve!(by: @manager)
      OpenLoam::Current.actor = nil
    end

    assert_equal "failed", action.reload.status
    assert_match(/may not set deleted_at/, action.error)
    assert_nil @excavator.reload.deleted_at
  end

  test "the approver's own field rules apply to what they approve" do
    action = stage({ "daily_rate" => 1 }, actor: @manager)

    with_tenant(@tenant) do
      OpenLoam::Current.actor = @employee
      # An employee cannot approve at all in the UI (require_role!), but the
      # model must not rely on the screen for the field-level half.
      assert_raises(OpenLoam::NotAuthorizedError) { action.send(:permitted_changeset, @excavator) }
      OpenLoam::Current.actor = nil
    end
  end
end
