require "test_helper"

# Loam::OpenApi: the auto-generated OpenAPI 3.1 document for the JSON API.
class LoamOpenApiTest < ActiveSupport::TestCase
  setup { @doc = Loam::OpenApi.document }

  test "the document has the OpenAPI 3.1 top-level shape" do
    assert_equal "3.1.0", @doc["openapi"]
    assert @doc["info"]["title"].present?
    assert @doc["info"]["version"].present?
    assert @doc["paths"].any?
    assert @doc["components"]["schemas"].any?
    assert @doc["components"]["securitySchemes"].key?("bearerAuth")
  end

  test "every entity with an api controller has all five CRUD operations, bearer-secured" do
    Loam::OpenApi.api_entities.each do |model|
      plural = model.model_name.plural
      collection = @doc["paths"]["/#{plural}"]
      member = @doc["paths"]["/#{plural}/{id}"]

      assert collection && member, "#{model.name} is missing its paths"
      assert collection.key?("get") && collection.key?("post"), "#{model.name} index/create"
      assert member.key?("get") && member.key?("patch") && member.key?("delete"), "#{model.name} show/update/delete"

      # bearer is required (top-level security) and unauthorized is documented
      assert_equal [ { "bearerAuth" => [] } ], @doc["security"]
      assert collection["post"]["responses"].key?("401"), "401 documented"
    end
  end

  test "the request body has writable fields but NEVER tenant_id or plumbing" do
    input = @doc["components"]["schemas"]["EquipmentInput"]["properties"]
    assert_equal %w[name daily_rate status], input.keys, "the declared writable fields"

    @doc["components"]["schemas"].each do |name, schema|
      next unless name.end_with?("Input")
      %w[tenant_id id created_at updated_at lock_version deleted_at].each do |plumbing|
        refute schema["properties"].key?(plumbing), "#{name} must not expose #{plumbing}"
      end
    end
  end

  test "the response schema includes readable fields and read-only id/timestamps" do
    props = @doc["components"]["schemas"]["Equipment"]["properties"]
    assert props.key?("name")
    assert props["id"]["readOnly"]
    assert props["created_at"]["readOnly"]
  end

  test "an encrypted field is typed as a plain string (no value leak, it's a schema)" do
    props = @doc["components"]["schemas"]["Customer"]["properties"]
    assert_equal "string", props["email"]["type"]
    assert_equal "string", props["tax_id"]["type"]
  end

  test "the tenancy guarantee is documented" do
    assert_match(/tenant-scoped/, @doc["x-tenancy"])
    assert_match(/tenant/, @doc["info"]["description"])
  end

  test "the markdown export renders the endpoints" do
    md = Loam::OpenApi.markdown
    assert_match(/# .+ API/, md)
    assert_match(%r{GET /api/equipment}, md)
    assert_match(/bearer token/, md)
  end
end

# The admin OpenAPI explorer.
class AdminApiDocsTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-apidocs")
    @mgr = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    @emp = User.create!(name: "Tomek", email: "tomek@example.test", password: "password")
    with_tenant(@tenant) do
      Loam::Membership.create!(user: @mgr, role: "manager")
      Loam::Membership.create!(user: @emp, role: "employee")
    end
  end

  def sign_in(email)
    post admin_session_path, params: { email: email, password: "password" }
  end

  test "a manager sees the server-rendered explorer (no external JS)" do
    sign_in("anna@example.test")
    get admin_api_docs_path

    assert_response :success
    assert_match "/api/equipment", response.body
    assert_match "bearer", response.body
    refute_match "swagger", response.body.downcase, "no swagger-ui pulled in"
    refute_match(/<script src=/, response.body, "no external JS")
  end

  test "the .json format serves the raw OpenAPI document" do
    sign_in("anna@example.test")
    get admin_api_docs_path(format: :json)

    assert_response :success
    doc = JSON.parse(response.body)
    assert_equal "3.1.0", doc["openapi"]
  end

  test "an employee may not read the API docs" do
    sign_in("tomek@example.test")
    get admin_api_docs_path
    assert_response :forbidden
  end
end
