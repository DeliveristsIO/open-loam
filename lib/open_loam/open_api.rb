require "json"

module Loam
  # Auto-generates an OpenAPI 3.1 document for the app's JSON API by
  # INTROSPECTING what Loam already knows — the generated `Api::<Plural>Controller`s,
  # each entity's columns/types, its exposed `FIELDS`, its custom fields, and that
  # every endpoint is bearer-authenticated and tenant-scoped. No hand-written
  # annotations, no external gem.
  #
  #   Loam::OpenApi.document   # => a Hash conforming to OpenAPI 3.1
  #   Loam::OpenApi.markdown   # => a Markdown rendering
  #
  # The document describes the SHAPE of the API only — never tenant data. It is
  # served at /admin/api_docs and exported by `bin/rails loam:openapi:export`.
  module OpenApi
    TYPE_MAP = {
      "string" => { "type" => "string" }, "text" => { "type" => "string" },
      "integer" => { "type" => "integer" }, "bigint" => { "type" => "integer" },
      "float" => { "type" => "number" }, "decimal" => { "type" => "number" },
      "boolean" => { "type" => "boolean" },
      "date" => { "type" => "string", "format" => "date" },
      "datetime" => { "type" => "string", "format" => "date-time" },
      "json" => { "type" => "object" }, "jsonb" => { "type" => "object" }
    }.freeze

    TENANCY_NOTE = "Every endpoint is tenant-scoped by the bearer token: a caller only ever reads or " \
                   "writes data in the token's OWN tenant — cross-tenant access is impossible.".freeze

    module_function

    def document
      {
        "openapi" => "3.1.0",
        "info" => info,
        "servers" => [ { "url" => "/api" } ],
        "security" => [ { "bearerAuth" => [] } ],
        "components" => { "securitySchemes" => security_schemes, "schemas" => schemas },
        "paths" => paths,
        "x-tenancy" => TENANCY_NOTE
      }
    end

    # The Loam entities that have a generated JSON API controller. Anonymous
    # subclasses (Class.new(Loam::TenantRecord), common in tests) have no name,
    # so model_name would raise "Class name cannot be blank" — skip them: a
    # nameless class has no controller or route to document anyway.
    def api_entities
      Rails.application.eager_load! if defined?(Rails) && Rails.respond_to?(:application)
      Loam::TenantRecord.descendants
                        .reject { |model| model.name.blank? }
                        .select { |model| controller_for(model) }
                        .sort_by(&:name)
    end

    def controller_for(model)
      # model_name.plural handles uncountables ("equipment"), unlike route_key
      # (which becomes "equipment_index").
      "Api::#{model.model_name.plural.camelize}Controller".safe_constantize
    end

    def info
      name = defined?(Rails) ? Rails.application.class.module_parent_name : "Loam"
      {
        "title" => "#{name} API",
        "version" => "1.0.0",
        "description" => "Auto-generated from the Loam entities. Bearer-token authenticated. #{TENANCY_NOTE}"
      }
    end

    def security_schemes
      { "bearerAuth" => { "type" => "http", "scheme" => "bearer",
                          "description" => "A Loam::ApiToken — identifies one user in one tenant." } }
    end

    def schemas
      api_entities.each_with_object({}) do |model, out|
        out[model.name] = entity_schema(model)
        out["#{model.name}Input"] = input_schema(model)
      end
    end

    def entity_schema(model)
      props = { "id" => { "type" => "integer", "readOnly" => true } }
      exposed_fields(model).each { |field| props[field] = column_schema(model, field) }
      custom_field_names(model).each { |name| props[name] = { "type" => "string", "description" => "custom field" } }
      %w[created_at updated_at].each { |ts| props[ts] = { "type" => "string", "format" => "date-time", "readOnly" => true } }
      { "type" => "object", "properties" => props }
    end

    # Request body: the writable, declared fields only — never id/tenant_id/
    # timestamps. Field-level write access is enforced per the token's role at
    # runtime (Loam::Policy), which a structural schema can't express per-role;
    # noted in the description rather than emitting a schema per role.
    def input_schema(model)
      props = {}
      exposed_fields(model).each { |field| props[field] = column_schema(model, field) }
      custom_field_names(model).each { |name| props[name] = { "type" => "string" } }
      {
        "type" => "object",
        "properties" => props,
        "description" => "Field-level write access applies per the token's role — a field the role may not write is ignored."
      }
    end

    def paths
      api_entities.each_with_object({}) do |model, out|
        plural = model.model_name.plural
        ref = { "$ref" => "#/components/schemas/#{model.name}" }
        input = { "$ref" => "#/components/schemas/#{model.name}Input" }

        out["/#{plural}"] = {
          "get" => operation("List #{plural}", "200" => array_response(ref)),
          "post" => operation("Create a #{model.name}", body: input, "201" => object_response(ref), "422" => error_response("validation failed"))
        }
        out["/#{plural}/{id}"] = {
          "parameters" => [ id_param ],
          "get" => operation("Fetch a #{model.name}", "200" => object_response(ref), "404" => error_response("not found")),
          "patch" => operation("Update a #{model.name}", body: input, "200" => object_response(ref), "422" => error_response("validation failed"), "404" => error_response("not found")),
          "delete" => operation("Soft-delete a #{model.name}", "204" => { "description" => "deleted" }, "404" => error_response("not found"))
        }
      end
    end

    # ---- markdown ----

    def markdown(doc = document)
      lines = [ "# #{doc['info']['title']}", "", doc["info"]["description"], "", "**Auth:** bearer token. **Tenancy:** #{doc['x-tenancy']}", "" ]
      doc["paths"].sort.each do |path, ops|
        ops.each do |method, op|
          next unless op.is_a?(Hash) && op["summary"]
          lines << "## `#{method.upcase} /api#{path}` — #{op['summary']}"
          lines << "Requires a bearer token. Responses: #{op['responses'].keys.join(', ')}."
          lines << ""
        end
      end
      lines.join("\n")
    end

    # ---- internals ----

    def exposed_fields(model)
      controller = controller_for(model)
      return controller::FIELDS.map(&:to_s) if controller.const_defined?(:FIELDS)

      # No declared FIELDS: fall back to columns, but NEVER surface an encrypted
      # column or its blind-index `_hash` (same exclusion as Loam::Export).
      encrypted = model.respond_to?(:loam_encrypted_attributes) ? model.loam_encrypted_attributes : []
      blind = model.respond_to?(:loam_searchable_encrypted_attributes) ? model.loam_searchable_encrypted_attributes.map { |a| "#{a}_hash" } : []
      model.column_names - plumbing(model) - encrypted - blind
    end

    def plumbing(model)
      %w[id tenant_id created_at updated_at lock_version deleted_at custom_fields]
    end

    def column_schema(model, field)
      column = model.columns_hash[field.to_s]
      return { "type" => "string" } unless column # a custom field or virtual

      TYPE_MAP.fetch(column.type.to_s, { "type" => "string" }).dup
    end

    def custom_field_names(model)
      return [] unless model.respond_to?(:custom_field_definitions) && Loam::Current.tenant

      model.custom_field_definitions.map(&:name)
    rescue StandardError
      []
    end

    def operation(summary, body: nil, **responses)
      responses = { "401" => error_response("missing or invalid token") }.merge(responses)
      op = { "summary" => summary, "responses" => responses }
      if body
        op["requestBody"] = { "required" => true, "content" => { "application/json" => { "schema" => body } } }
      end
      op
    end

    def object_response(ref) = { "description" => "ok", "content" => { "application/json" => { "schema" => ref } } }

    def array_response(ref)
      { "description" => "ok", "content" => { "application/json" => { "schema" => { "type" => "array", "items" => ref } } } }
    end

    def error_response(desc)
      { "description" => desc, "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => { "error" => { "type" => "string" } } } } } }
    end

    def id_param
      { "name" => "id", "in" => "path", "required" => true, "schema" => { "type" => "integer" } }
    end
  end
end
