module Loam
  # An MCP (Model Context Protocol) server surface exposing Loam to an AI agent —
  # tools-only v1 (L-302). It lets an agent DISCOVER the domain (entities, schema,
  # policy, workflow) and READ tenant-scoped records, and PROPOSE writes that are
  # STAGED for human approval — never committed. Everything runs inside the
  # tenant + actor of the API token the server authenticated with; whatever that
  # user may do, no more. Approval authority stays with a human in the admin.
  #
  # Two layers: the tool methods (pure, assume Loam::Current is established) and
  # `handle_jsonrpc` (a pure JSON-RPC dispatcher for initialize / tools/list /
  # tools/call). The stdio transport (newline-delimited JSON-RPC) lives in
  # Loam::Mcp::Server.
  #
  # SECURITY posture, reusing Loam's existing gates:
  #   * entity names resolve against an allowlist (API-exposed TenantRecord
  #     descendants), never a bare constantize;
  #   * query filters/order are whitelisted to real columns (or a known custom
  #     field, which carries the L-711 read-ACL); a filter on a field the role
  #     can't read is refused (no inference oracle);
  #   * query output emits only policy-readable fields per record (encrypted
  #     values decrypted, blind-index columns dropped);
  #   * a staged write accepts only policy-writable columns, refuses the workflow
  #     column (that goes through a transition), and refuses id/tenant_id/
  #     lock_version.
  module Mcp
    class ToolError < StandardError; end

    PROTOCOL_VERSION = "2025-06-18".freeze
    MAX_LIMIT = 100
    FILTER_OPS = %w[eq neq contains gt gte lt lte present].freeze

    TOOLS = [
      {
        name: "list_entities",
        description: "List the business entities available in this Loam tenant.",
        inputSchema: { type: "object", properties: {}, additionalProperties: false }
      },
      {
        name: "describe_entity",
        description: "Describe one entity: its columns and types, custom fields, workflow, and which fields the current role may read/write.",
        inputSchema: {
          type: "object",
          properties: { entity: { type: "string", description: "Entity name, e.g. \"Equipment\"." } },
          required: [ "entity" ], additionalProperties: false
        }
      },
      {
        name: "query_entity",
        description: "Read tenant-scoped records of an entity. Returns only fields the current role may read. Filters and sort are whitelisted; limit is capped at 100.",
        inputSchema: {
          type: "object",
          properties: {
            entity: { type: "string" },
            filters: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  field: { type: "string" },
                  op: { type: "string", enum: FILTER_OPS },
                  value: {}
                },
                required: [ "field" ], additionalProperties: false
              }
            },
            order: { type: "string", description: "A real column name to sort by." },
            dir: { type: "string", enum: [ "asc", "desc" ] },
            limit: { type: "integer", minimum: 1, maximum: MAX_LIMIT }
          },
          required: [ "entity" ], additionalProperties: false
        }
      },
      {
        name: "stage_write",
        description: "PROPOSE an update to one record. It is staged as a Loam PendingAction for a human manager to approve — it does NOT take effect until approved. Only policy-writable columns are accepted; the workflow column is refused (use a transition).",
        inputSchema: {
          type: "object",
          properties: {
            entity: { type: "string" },
            id: { type: "integer" },
            changes: { type: "object", description: "field => new value, real writable columns only." }
          },
          required: [ "entity", "id", "changes" ], additionalProperties: false
        }
      }
    ].freeze

    module_function

    # --- entity allowlist ---

    def entities
      # Models are lazy-loaded (Zeitwerk), so `descendants` is only complete after
      # an eager load — same as Loam::OpenApi's discovery.
      Rails.application.eager_load! if defined?(Rails) && Rails.respond_to?(:application)
      Loam::TenantRecord.descendants
                        .reject { |model| model.name.blank? }
                        .select { |model| api_exposed?(model) }
                        .sort_by(&:name)
    end

    def api_exposed?(model)
      "Api::#{model.model_name.plural.camelize}Controller".safe_constantize.present?
    end

    def resolve!(entity)
      name = entity.to_s
      entities.find { |m| m.name == name || m.model_name.plural == name } ||
        raise(ToolError, "unknown entity #{entity.inspect}")
    end

    # --- tools ---

    def list_entities
      { entities: entities.map { |m| { name: m.name, plural: m.model_name.plural } } }
    end

    def describe_entity(entity:)
      model = resolve!(entity)
      policy = Loam::Policy.for(model.new)

      columns = model.columns.reject { |c| c.name.end_with?("_hash") }.map do |col|
        { name: col.name, type: col.sql_type_metadata.type.to_s,
          readable: policy.readable?(col.name), writable: policy.writable?(col.name) }
      end

      custom = if model.respond_to?(:custom_field_definitions)
        model.custom_field_definitions.map do |definition|
          { name: definition.name, type: definition.field_type,
            readable: policy.custom_field_readable?(definition.name),
            writable: policy.custom_field_writable?(definition.name) }
        end
      else
        []
      end

      workflow = if model.respond_to?(:loam_workflow) && model.loam_workflow
        wf = model.loam_workflow
        { column: wf.column, states: wf.states,
          transitions: wf.transitions.values.map { |t| { name: t.name.to_s, from: t.from, to: t.to, roles: Array(t.roles).map(&:to_s) } } }
      end

      { name: model.name, columns: columns, custom_fields: custom, workflow: workflow }.compact
    end

    def query_entity(entity:, filters: [], order: nil, dir: "asc", limit: MAX_LIMIT)
      model = resolve!(entity)
      policy = Loam::Policy.for(model.new)
      scope = apply_filters(model, model.all, filters, policy)
      scope = apply_order(model, scope, order, dir)
      capped = [ [ limit.to_i, 1 ].max, MAX_LIMIT ].min

      records = scope.limit(capped).map { |record| serialize(record, policy) }
      { entity: model.name, count: records.size, records: records }
    end

    def stage_write(entity:, id:, changes:)
      model = resolve!(entity)
      record = model.find(id) # tenant-scoped
      policy = Loam::Policy.for(record)
      workflow_column = model.respond_to?(:loam_workflow) ? model.loam_workflow&.column.to_s : nil

      clean = {}
      (changes || {}).each do |field, value|
        field = field.to_s
        raise ToolError, "#{field} cannot be set" if %w[id tenant_id lock_version].include?(field)
        raise ToolError, "#{field} changes go through a workflow transition, not a direct write" if field == workflow_column

        if model.column_names.include?(field)
          raise ToolError, "#{field} is not writable for this role" unless policy.writable?(field)
          clean[field] = value
        elsif custom_field?(model, field)
          raise ToolError, "custom-field writes over MCP are not supported in v1"
        else
          raise ToolError, "unknown field #{field.inspect}"
        end
      end
      raise ToolError, "no writable changes" if clean.empty?

      action = Loam::PendingActions.stage(
        summary: "MCP proposal: update #{model.name}##{id}",
        on: record, action: :update, changes: clean
      )
      { staged: true, pending_action_id: action.id, summary: action.summary, changes: clean,
        note: "Staged for human approval — not applied until a manager approves it." }
    end

    # --- protocol ---

    def call_tool(name, args)
      kwargs = (args || {}).transform_keys(&:to_sym)
      case name
      when "list_entities"  then list_entities
      when "describe_entity" then describe_entity(**kwargs.slice(:entity))
      when "query_entity"   then query_entity(**kwargs.slice(:entity, :filters, :order, :dir, :limit))
      when "stage_write"    then stage_write(**kwargs.slice(:entity, :id, :changes))
      else raise ToolError, "unknown tool #{name.inspect}"
      end
    end

    # Pure JSON-RPC dispatch. Returns a response Hash, or nil for a notification
    # (no reply). Never raises for tool faults — those become an isError result.
    def handle_jsonrpc(request)
      id = request["id"]
      case request["method"]
      when "initialize"
        ok(id, protocolVersion: request.dig("params", "protocolVersion") || PROTOCOL_VERSION,
               capabilities: { tools: {} },
               serverInfo: { name: "loam", version: Loam::VERSION })
      when "tools/list"
        ok(id, tools: TOOLS)
      when "tools/call"
        begin
          data = call_tool(request.dig("params", "name"), request.dig("params", "arguments"))
          ok(id, content: [ { type: "text", text: JSON.generate(data) } ])
        rescue ToolError, Loam::Error, ActiveRecord::RecordNotFound => error
          ok(id, isError: true, content: [ { type: "text", text: error.message } ])
        end
      when "notifications/initialized", "notifications/cancelled", nil
        nil # notifications get no response
      else
        err(id, -32601, "method not found: #{request["method"]}")
      end
    end

    # --- internals ---

    def apply_filters(model, scope, filters, policy)
      Array(filters).each do |raw|
        field = raw["field"].to_s
        op = (raw["op"] || "eq").to_s
        raise ToolError, "unknown op #{op.inspect}" unless FILTER_OPS.include?(op)
        value = raw["value"]

        if model.column_names.include?(field)
          raise ToolError, "#{field} is not readable for this role" unless policy.readable?(field)
          scope = column_filter(model, scope, field, op, value)
        elsif custom_field?(model, field)
          # CustomFieldIndex.filter carries its own L-711 read-ACL for the current
          # actor; surface its refusal as a clean tool error.
          begin
            scope = scope.merge(Loam::CustomFieldIndex.filter(model, field, op, value))
          rescue Loam::FieldAccessError => error
            raise ToolError, error.message
          end
        else
          raise ToolError, "unknown field #{field.inspect}"
        end
      end
      scope
    end

    def column_filter(model, scope, field, op, value)
      column = model.connection.quote_column_name(field) # field is a real column name (whitelisted)
      case op
      when "eq"       then scope.where(field => value)
      when "neq"      then scope.where.not(field => value)
      when "contains" then scope.where("#{column} LIKE ?", "%#{value.to_s.gsub(/[\\%_]/) { |c| "\\#{c}" }}%")
      when "present"  then scope.where.not(field => [ nil, "" ])
      when "gt"       then scope.where("#{column} > ?", value)
      when "gte"      then scope.where("#{column} >= ?", value)
      when "lt"       then scope.where("#{column} < ?", value)
      when "lte"      then scope.where("#{column} <= ?", value)
      end
    end

    def apply_order(model, scope, order, dir)
      return scope.order(id: :asc) if order.blank?
      raise ToolError, "unknown sort column #{order.inspect}" unless model.column_names.include?(order.to_s)

      direction = dir.to_s.casecmp("desc").zero? ? :desc : :asc
      scope.reorder(order.to_s => direction)
    end

    def serialize(record, policy)
      model = record.class
      encrypted = model.respond_to?(:loam_encrypted_attributes) ? model.loam_encrypted_attributes.map(&:to_s) : []

      json = {}
      policy.readable_fields(model.column_names).each do |col|
        next if col.end_with?("_hash")
        json[col] = encrypted.include?(col) ? record.public_send(col) : record[col]
      end
      if model.respond_to?(:custom_field_definitions)
        model.custom_field_definitions.each do |definition|
          json["cf_#{definition.name}"] = record.custom_field(definition.name) if policy.custom_field_readable?(definition.name)
        end
      end
      json
    end

    def custom_field?(model, field)
      model.respond_to?(:custom_field_definitions) && model.custom_field_definitions.exists?(name: field)
    end

    def ok(id, **result)
      { "jsonrpc" => "2.0", "id" => id, "result" => result }
    end

    def err(id, code, message)
      { "jsonrpc" => "2.0", "id" => id, "error" => { "code" => code, "message" => message } }
    end
  end
end
