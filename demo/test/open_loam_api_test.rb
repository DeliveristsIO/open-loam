require "test_helper"

# The REST API: a bearer token identifies one user in one tenant, and from
# there every ordinary OpenLoam rule applies — tenant isolation, policies, field
# level permissions, custom fields.
class OpenLoamApiTest < ActionDispatch::IntegrationTest
  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-api")
    @krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-api")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    @tomek = User.create!(name: "Tomek", email: "tomek@example.test", password: "password")

    with_tenant(@warsaw) do
      OpenLoam::Membership.create!(user: @anna, role: "manager")
      OpenLoam::Membership.create!(user: @tomek, role: "employee")
      @manager_token = OpenLoam::ApiToken.create!(user: @anna, label: "ops script").token
      @employee_token = OpenLoam::ApiToken.create!(user: @tomek, label: "scanner").token
      Equipment.create!(name: "Excavator", daily_rate: 950, status: "available")
      OpenLoam::FieldDefinition.create!(entity_type: "Equipment", name: "serial_number", field_type: "string")
    end

    with_tenant(@krakow) do
      OpenLoam::Membership.create!(user: @anna, role: "manager")
      @krakow_token = OpenLoam::ApiToken.create!(user: @anna, label: "krakow ops").token
      Equipment.create!(name: "Scaffolding", daily_rate: 80, status: "available")
    end
  end

  test "no token is a 401" do
    get "/api/equipment"

    assert_response :unauthorized
    assert_equal "unauthorized", response.parsed_body["error"]
  end

  test "an unknown token is a 401" do
    get "/api/equipment", headers: bearer("nonsense")

    assert_response :unauthorized
  end

  test "a token sees only its own tenant's records" do
    get "/api/equipment", headers: bearer(@manager_token)

    assert_response :success
    assert_equal [ "Excavator" ], response.parsed_body.map { |r| r["name"] }

    get "/api/equipment", headers: bearer(@krakow_token)

    assert_equal [ "Scaffolding" ], response.parsed_body.map { |r| r["name"] }
  end

  test "using a token records when it was last used" do
    token = with_tenant(@warsaw) { OpenLoam::ApiToken.find_by(token_digest: OpenLoam::ApiToken.digest(@manager_token)) }
    assert_nil token.last_used_at

    get "/api/equipment", headers: bearer(@manager_token)

    assert with_tenant(@warsaw) { OpenLoam::ApiToken.find_by(token_digest: OpenLoam::ApiToken.digest(@manager_token)).last_used_at }
  end

  test "a manager may set a manager-only field" do
    post "/api/equipment", params: { equipment: { name: "Crane", daily_rate: 1200, status: "available" } },
                           headers: bearer(@manager_token), as: :json

    assert_response :created
    assert_equal "1200.0", response.parsed_body["daily_rate"].to_s
  end

  test "an employee's write of a manager-only field is dropped, not honoured" do
    post "/api/equipment", params: { equipment: { name: "Drill", daily_rate: 999, status: "available" } },
                           headers: bearer(@employee_token), as: :json

    assert_response :created
    assert_equal "Drill", response.parsed_body["name"], "fields the role may write still land"
    assert_nil response.parsed_body["daily_rate"],
               "daily_rate is manager-only (EquipmentPolicy), so it must be filtered out of the permit list"
  end

  test "custom fields round-trip through the API" do
    post "/api/equipment",
         params: { equipment: { name: "Mixer", daily_rate: 120, status: "available" },
                   custom_fields: { serial_number: "SN-42" } },
         headers: bearer(@manager_token), as: :json

    assert_response :created
    assert_equal({ "serial_number" => "SN-42" }, response.parsed_body["custom_fields"])

    id = response.parsed_body["id"]
    get "/api/equipment/#{id}", headers: bearer(@manager_token)

    assert_equal "SN-42", response.parsed_body.dig("custom_fields", "serial_number")
  end

  test "a record from another tenant is not found, not forbidden" do
    krakow_id = with_tenant(@krakow) { Equipment.first.id }

    get "/api/equipment/#{krakow_id}", headers: bearer(@manager_token)

    assert_response :not_found
  end

  test "a policy refusal is a 403" do
    id = with_tenant(@warsaw) { Equipment.first.id }

    # EquipmentPolicy#destroy? is manager-only.
    delete "/api/equipment/#{id}", headers: bearer(@employee_token)
    assert_response :forbidden

    delete "/api/equipment/#{id}", headers: bearer(@manager_token)
    assert_response :no_content
  end

  private

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
