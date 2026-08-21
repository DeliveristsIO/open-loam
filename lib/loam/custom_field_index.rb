module Loam
  # The read-model index for custom fields (Loam::CustomFieldValue) — a typed-EAV
  # projection that makes custom-field filter/sort/search index-backed.
  #
  #   Loam::CustomFieldIndex.filter(DamageReport, "severity", "eq", "critical")  # a relation
  #   Loam::CustomFieldIndex.order(DamageReport, "severity", :asc)
  #   Loam::CustomFieldIndex.reindex(DamageReport)                               # rebuild
  #
  # SAFETY: `field_key` must name a real Loam::FieldDefinition (no arbitrary
  # keys); values are cast to the declared type; queries are tenant-scoped
  # throughout (index rows carry tenant_id, the model relation is default-scoped),
  # so a filter can't reach across tenants. Encrypted data lives in real columns,
  # never in a custom field — nothing encrypted is projected here.
  module CustomFieldIndex
    OPS = %w[eq neq gt gte lt lte contains present blank].freeze

    module_function

    # --- maintenance (called from Loam::CustomFields) ---

    # Re-project one record's custom fields (delete + insert). Soft-delete keeps
    # the rows (the filter's base scope hides the record anyway — the same
    # decision as the L-912 search token driver); a hard destroy removes them.
    def project(record)
      model = record.class
      return unless model.respond_to?(:custom_field_definitions)

      type = index_type(model)
      Loam::CustomFieldValue.where(indexable_type: type, indexable_id: record.id).delete_all

      rows = model.custom_field_definitions.filter_map { |definition| row_for(record, definition, type) }
      Loam::CustomFieldValue.insert_all(rows) if rows.any?
    end

    def remove(record)
      Loam::CustomFieldValue.where(indexable_type: index_type(record.class), indexable_id: record.id).delete_all
    end

    def reindex(model)
      Loam::CustomFieldValue.where(indexable_type: index_type(model)).delete_all
      model.find_each { |record| project(record) }
    end

    # --- query API ---

    def filter(model, field_key, op, value = nil)
      field_key = field_key.to_s
      refuse_unknown_field!(model, field_key)
      raise Loam::Error, "unknown custom-field op #{op.inspect}" unless OPS.include?(op.to_s)

      rows = base(model).where(field_key: field_key)

      if op.to_s == "blank"
        present_ids = rows.where.not(value_text: [ nil, "" ]).select(:indexable_id)
        return model.where.not(id: present_ids)
      end

      model.where(id: predicate(rows, op.to_s, value).select(:indexable_id))
    end

    # Order a model's records by an indexed custom field (value_text — good for
    # dictionary/string fields, the common case; numeric-aware ordering is a
    # follow-up). Records with no value sort last (LEFT JOIN + NULLs).
    def order(model, field_key, dir = :asc)
      refuse_unknown_field!(model, field_key.to_s)
      table = Loam::CustomFieldValue.table_name
      conn = model.connection
      join = "LEFT JOIN #{table} ON #{table}.indexable_type = #{conn.quote(index_type(model))} " \
             "AND #{table}.indexable_id = #{model.table_name}.id " \
             "AND #{table}.field_key = #{conn.quote(field_key.to_s)} " \
             "AND #{table}.tenant_id = #{Loam.tenant!.id}"
      model.joins(join).order(Arel.sql("#{table}.value_text #{dir.to_s.casecmp('desc').zero? ? 'DESC' : 'ASC'}"))
    end

    # --- internals ---

    def base(model)
      Loam::CustomFieldValue.where(indexable_type: index_type(model)) # tenant-scoped by default_scope
    end

    def index_type(model_or_class)
      klass = model_or_class.is_a?(Class) ? model_or_class : model_or_class.class
      klass.base_class.name
    end

    def predicate(rows, op, value)
      case op
      when "eq"       then rows.where(value_text: value.to_s)
      when "neq"      then rows.where.not(value_text: value.to_s)
      when "contains" then rows.where("value_text LIKE ?", "%#{sanitize_like(value)}%")
      when "present"  then rows.where.not(value_text: [ nil, "" ])
      when "gt"       then numeric(rows, value, ">")
      when "gte"      then numeric(rows, value, ">=")
      when "lt"       then numeric(rows, value, "<")
      when "lte"      then numeric(rows, value, "<=")
      end
    end

    # Numeric comparisons hit the indexed value_number column.
    def numeric(rows, value, operator)
      rows.where("value_number #{operator} ?", value.to_f)
    end

    def row_for(record, definition, type)
      value = (record.custom_field(definition.name) rescue nil)
      return nil if value.nil?

      # ALL value columns are present (nil when unused) so insert_all sees a
      # uniform key set across every row.
      row = {
        tenant_id: record.tenant_id, indexable_type: type, indexable_id: record.id,
        field_key: definition.name, value_text: value.to_s,
        value_number: nil, value_boolean: nil, value_datetime: nil
      }
      case definition.field_type
      when "integer", "decimal" then row[:value_number] = value.to_f
      when "boolean"            then row[:value_boolean] = ActiveModel::Type::Boolean.new.cast(value)
      when "date", "datetime"   then row[:value_datetime] = (Time.zone.parse(value.to_s) rescue nil)
      end
      row
    end

    def refuse_unknown_field!(model, field_key)
      known = model.respond_to?(:custom_field_definitions) && model.custom_field_definitions.exists?(name: field_key)
      raise Loam::Error, "no custom field #{field_key.inspect} on #{model.name}" unless known
    end

    def sanitize_like(value)
      value.to_s.gsub(/[\\%_]/) { |c| "\\#{c}" }
    end
  end
end
