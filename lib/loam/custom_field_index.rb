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

      if covered?(model, field_key)
        self.partial = false
        index_filter(model, field_key, op, value)
      else
        # CORRECTNESS OVER SPEED: the index is known-incomplete for this field
        # (coverage gap), so serve an authoritative JSON-scan result — never a
        # silently-partial index set — AND enqueue a background reindex (deduped)
        # to heal the gap so subsequent queries are fast again. `partial?` lets
        # the caller surface an honest "results may be incomplete, reindexing…".
        self.partial = true
        schedule_reindex(model)
        json_filter(model, field_key, op, value)
      end
    end

    # The index-backed relation (used when coverage is complete).
    def index_filter(model, field_key, op, value)
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
      # The LEFT JOIN keeps EVERY record (un-indexed ones sort as NULL), so an
      # incomplete index mis-orders the gap but never drops a row. Flag it and
      # heal in the background.
      unless covered?(model, field_key.to_s)
        self.partial = true
        schedule_reindex(model)
      end
      table = Loam::CustomFieldValue.table_name
      conn = model.connection
      join = "LEFT JOIN #{table} ON #{table}.indexable_type = #{conn.quote(index_type(model))} " \
             "AND #{table}.indexable_id = #{model.table_name}.id " \
             "AND #{table}.field_key = #{conn.quote(field_key.to_s)} " \
             "AND #{table}.tenant_id = #{Loam.tenant!.id}"
      model.joins(join).order(Arel.sql("#{table}.value_text #{dir.to_s.casecmp('desc').zero? ? 'DESC' : 'ASC'}"))
    end

    # --- coverage + self-heal (L-919) ---

    # How complete the index is for a field: how many live records HAVE a value
    # (the authoritative JSON column) vs how many index rows exist. The trust
    # signal — "9,980 of 10,000 indexed" tells an operator whether the index is
    # complete or drifting (legacy data, a bulk write that bypassed the hook, a
    # field def added before a backfill). Counting expected does a JSON pass, so
    # it's a periodic READOUT, never a per-row query cost.
    def coverage(model, field_key)
      field_key = field_key.to_s
      exp = expected(model, field_key)
      got = indexed(model, field_key)
      { field_key: field_key, expected: exp, indexed: got, complete: got >= exp,
        ratio: exp.zero? ? 1.0 : (got.to_f / exp) }
    end

    def covered?(model, field_key)
      coverage(model, field_key)[:complete]
    end

    def indexed(model, field_key)
      base(model).where(field_key: field_key.to_s).where.not(value_text: [ nil, "" ]).count
    end

    def expected(model, field_key)
      return 0 unless model.column_names.include?("custom_fields")

      key = field_key.to_s
      model.pluck(:custom_fields).count { |cf| cf.is_a?(Hash) && cf[key].to_s.strip != "" }
    end

    # Was the last filter/order served over an incomplete index? The admin surfaces
    # this as an honest "results may be incomplete, reindexing…".
    def partial?
      Thread.current[:loam_index_partial] == true
    end

    def partial=(value)
      Thread.current[:loam_index_partial] = value
    end

    # Enqueue a background reindex to heal a gap — DEDUPED so a hot gappy field
    # doesn't enqueue one per request. In-process dedup here (single-process
    # prototype); a DB/cache marker is the multi-process path.
    def schedule_reindex(model)
      key = [ Loam.tenant!.id, model.base_class.name ]
      return if pending_reindex.include?(key)

      pending_reindex << key
      Loam::CustomFieldReindexJob.perform_later(Loam.tenant!.id, model.base_class.name)
    end

    def clear_pending(tenant_id, model_name)
      pending_reindex.delete([ tenant_id, model_name ])
    end

    def reset_pending!
      @pending_reindex = Set.new
    end

    def pending_reindex
      @pending_reindex ||= Set.new
    end

    # Authoritative correct filter over the JSON column — DB-agnostic (reads each
    # record's cast custom_field), used only as the fallback when the index is
    # incomplete. Slow (a scan), which is exactly why the heal runs.
    def json_filter(model, field_key, op, value)
      ids = model.find_each.select { |record| json_match?(record, field_key, op, value) }.map(&:id)
      model.where(id: ids)
    end

    def json_match?(record, field_key, op, value)
      actual = (record.custom_field(field_key) rescue nil)
      case op.to_s
      when "eq"       then actual.to_s == value.to_s
      when "neq"      then actual.to_s != value.to_s
      when "present"  then actual.to_s.strip != ""
      when "blank"    then actual.to_s.strip == ""
      when "contains" then actual.to_s.include?(value.to_s)
      when "gt"       then actual.to_f > value.to_f
      when "gte"      then actual.to_f >= value.to_f
      when "lt"       then actual.to_f < value.to_f
      when "lte"      then actual.to_f <= value.to_f
      end
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
