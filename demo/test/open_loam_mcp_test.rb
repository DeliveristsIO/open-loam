require "test_helper"

# L-302: the MCP tool surface exposes OpenLoam to an agent — discover, read
# (policy-aware, tenant-scoped), and PROPOSE writes staged for human approval.
# The pure protocol dispatch (handle_jsonrpc) is tested without any transport.
class OpenLoamMcpTest < ActiveSupport::TestCase
  setup do
    @tenant = OpenLoam::Tenant.create!(name: "Branch", slug: "warsaw-mcp")
    @manager = User.create!(name: "Mgr", email: "mgr-mcp@example.test", password: "password")
    @clerk = User.create!(name: "Clerk", email: "clerk-mcp@example.test", password: "password")
    with_tenant(@tenant) do
      OpenLoam::Membership.create!(user: @manager, role: "manager")
      OpenLoam::Membership.create!(user: @clerk, role: "employee")
      OpenLoam::FieldDefinition.create!(entity_type: "Equipment", name: "clearance",
                                    field_type: "string", readable_roles: [ "manager" ])
    end
  end

  # --- discovery ---

  test "list_entities returns the API-exposed entities" do
    with_tenant(@tenant, actor: @manager) do
      names = OpenLoam::Mcp.list_entities[:entities].map { |e| e[:name] }
      assert_includes names, "Equipment"
      assert_includes names, "Lead"
    end
  end

  test "describe_entity reports columns, custom fields, and workflow" do
    with_tenant(@tenant, actor: @manager) do
      lead = OpenLoam::Mcp.describe_entity(entity: "Lead")
      assert_equal "Lead", lead[:name]
      assert lead[:workflow][:states].include?("won")
      assert(lead[:workflow][:transitions].any? { |t| t[:name] == "win" && t[:roles] == [ "manager" ] })

      eq = OpenLoam::Mcp.describe_entity(entity: "Equipment")
      assert_nil eq[:workflow], "Equipment has no workflow"
      assert(eq[:custom_fields].any? { |f| f[:name] == "clearance" })
    end
  end

  test "an unknown entity is a tool error" do
    with_tenant(@tenant, actor: @manager) do
      assert_raises(OpenLoam::Mcp::ToolError) { OpenLoam::Mcp.describe_entity(entity: "Nope") }
    end
  end

  # --- read, policy-aware ---

  test "query_entity returns records and drops fields the role can't read" do
    with_tenant(@tenant, actor: @manager) do
      eq = Equipment.create!(name: "Digger", daily_rate: 100, status: "available")
      eq.set_custom_field("clearance", "top-secret"); eq.save!
    end

    with_tenant(@tenant, actor: @manager) do
      row = OpenLoam::Mcp.query_entity(entity: "Equipment")[:records].first
      assert_equal "Digger", row["name"]
      assert_equal "top-secret", row["cf_clearance"], "a manager sees the restricted field"
    end
    with_tenant(@tenant, actor: @clerk) do
      row = OpenLoam::Mcp.query_entity(entity: "Equipment")[:records].first
      assert_equal "Digger", row["name"]
      refute row.key?("cf_clearance"), "a clerk never sees the manager-only field"
    end
  end

  test "query filters and sort are whitelisted; limit is capped" do
    with_tenant(@tenant, actor: @manager) do
      Equipment.create!(name: "A", daily_rate: 10, status: "available")
      Equipment.create!(name: "B", daily_rate: 20, status: "available")

      result = OpenLoam::Mcp.query_entity(entity: "Equipment", filters: [ { "field" => "name", "op" => "eq", "value" => "A" } ])
      assert_equal 1, result[:count]

      assert_raises(OpenLoam::Mcp::ToolError) { OpenLoam::Mcp.query_entity(entity: "Equipment", order: "name); DROP TABLE") }
      assert_raises(OpenLoam::Mcp::ToolError) { OpenLoam::Mcp.query_entity(entity: "Equipment", filters: [ { "field" => "bogus" } ]) }
    end

    with_tenant(@tenant, actor: @clerk) do
      # filtering on a field the role can't read is refused (no inference oracle)
      assert_raises(OpenLoam::Mcp::ToolError) do
        OpenLoam::Mcp.query_entity(entity: "Equipment", filters: [ { "field" => "clearance", "op" => "eq", "value" => "x" } ])
      end
    end
  end

  # --- staged writes only ---

  test "stage_write stages a PendingAction and never commits" do
    id = with_tenant(@tenant, actor: @manager) { Equipment.create!(name: "Digger", daily_rate: 100, status: "available").id }

    with_tenant(@tenant, actor: @manager) do
      before = OpenLoam::PendingAction.count
      result = OpenLoam::Mcp.stage_write(entity: "Equipment", id: id, changes: { "name" => "Excavator" })
      assert result[:staged]
      assert_equal before + 1, OpenLoam::PendingAction.count
      assert_equal "Digger", Equipment.find(id).name, "the record is NOT mutated — only staged"
    end
  end

  test "stage_write refuses the workflow column and unwritable fields" do
    lead_id = with_tenant(@tenant, actor: @manager) { Lead.create!(source: "web", value: 100, state: "new").id }

    with_tenant(@tenant, actor: @manager) do
      err = assert_raises(OpenLoam::Mcp::ToolError) { OpenLoam::Mcp.stage_write(entity: "Lead", id: lead_id, changes: { "state" => "won" }) }
      assert_match "transition", err.message
    end
    with_tenant(@tenant, actor: @clerk) do
      # value is manager-only (LeadPolicy) — a clerk can't even stage it
      assert_raises(OpenLoam::Mcp::ToolError) { OpenLoam::Mcp.stage_write(entity: "Lead", id: lead_id, changes: { "value" => 999 }) }
    end
  end

  # --- protocol ---

  test "initialize echoes the client's protocol version and advertises tools" do
    reply = OpenLoam::Mcp.handle_jsonrpc("jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                                     "params" => { "protocolVersion" => "2025-06-18" })
    assert_equal "2025-06-18", reply["result"][:protocolVersion]
    assert_equal({ tools: {} }, reply["result"][:capabilities])
    assert_equal "open_loam", reply["result"][:serverInfo][:name]
  end

  test "tools/list returns the four tools with valid JSON-Schema inputs" do
    reply = OpenLoam::Mcp.handle_jsonrpc("jsonrpc" => "2.0", "id" => 2, "method" => "tools/list")
    tools = reply["result"][:tools]
    assert_equal %w[list_entities describe_entity query_entity stage_write], tools.map { |t| t[:name] }
    assert(tools.all? { |t| t[:inputSchema][:type] == "object" })
  end

  test "tools/call wraps the result in a content block; a notification gets no reply" do
    with_tenant(@tenant, actor: @manager) do
      reply = OpenLoam::Mcp.handle_jsonrpc("jsonrpc" => "2.0", "id" => 3, "method" => "tools/call",
                                       "params" => { "name" => "list_entities", "arguments" => {} })
      text = reply["result"][:content].first[:text]
      assert_includes JSON.parse(text)["entities"].map { |e| e["name"] }, "Equipment"
    end
    assert_nil OpenLoam::Mcp.handle_jsonrpc("jsonrpc" => "2.0", "method" => "notifications/initialized")
  end

  test "a tool fault becomes an isError result, not a JSON-RPC error" do
    with_tenant(@tenant, actor: @manager) do
      reply = OpenLoam::Mcp.handle_jsonrpc("jsonrpc" => "2.0", "id" => 4, "method" => "tools/call",
                                       "params" => { "name" => "describe_entity", "arguments" => { "entity" => "Nope" } })
      assert reply["result"][:isError]
    end
  end
end
