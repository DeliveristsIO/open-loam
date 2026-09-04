require "csv"
require "set"

module OpenLoam
  # CSV import mapping engine — reusable, tenant-scoped, policy-safe.
  #
  #   OpenLoam::Import.preview(csv)                       # headers + first rows for the mapping UI
  #   OpenLoam::Import.run(csv, model:, mapping:, actor:, # map CSV header => field
  #                    match_key: "name",             # update-or-create by a key (nil = create-only)
  #                    dry_run: true,                 # validate + report, commit nothing
  #                    progress: progress_job)        # advance a OpenLoam::ProgressJob per row
  #
  # Safety: the mapping may only target fields the actor's role can WRITE (real
  # columns + declared custom fields); tenant_id, plumbing, and non-permitted
  # fields are refused (no crafted mapping can smuggle a value past the policy).
  # Each row is its OWN save — a bad row is logged (row number + reason) and
  # SKIPPED, never half-committed, and the import continues. Records land in the
  # current tenant automatically (TenantRecord). Malformed CSV is a clean error,
  # not a crash.
  module Import
    PLUMBING = %w[id tenant_id created_at updated_at lock_version deleted_at custom_fields].freeze

    Result = Struct.new(:created, :updated, :failed, :errors, keyword_init: true) do
      def total = created + updated + failed
      def to_h = { created: created, updated: updated, failed: failed, errors: errors }
    end

    module_function

    # Resolve an entity_type string to a model — ONLY a OpenLoam::TenantRecord
    # subclass (never an arbitrary constant), so an import target can't be
    # smuggled to a global model like User (same guard as the business-rules
    # engine).
    def allowed_model(entity_type)
      klass = entity_type.to_s.safe_constantize
      unless klass.is_a?(Class) && klass < OpenLoam::TenantRecord
        raise OpenLoam::Error, "import target #{entity_type.inspect} is not a OpenLoam entity"
      end

      klass
    end

    def preview(csv_string, limit: 5)
      rows = safe_parse(csv_string)
      { headers: rows.first || [], rows: rows.drop(1).first(limit) }
    end

    # The fields a mapping may target for `model` given `actor`'s role.
    def allowed_targets(model, actor)
      policy = policy_for(model, actor)
      columns = (model.column_names - PLUMBING).select { |c| policy.writable?(c) }
      customs = if model.respond_to?(:custom_field_definitions)
                  model.custom_field_definitions.map(&:name).select { |n| policy.custom_field_writable?(n) }
                else
                  []
                end
      (columns + customs).to_set
    end

    def run(csv_string, model:, mapping:, actor:, match_key: nil, dry_run: false, progress: nil)
      refuse_bad_mapping!(mapping, allowed_targets(model, actor))

      rows = safe_parse(csv_string)
      headers = rows.first || []
      result = Result.new(created: 0, updated: 0, failed: 0, errors: [])

      rows.drop(1).each_with_index do |row, index|
        line = index + 2 # human row number (1-based + header)
        begin
          attrs = row_attributes(headers, row, mapping)
          record, is_new = find_or_build(model, attrs, match_key)
          assign(record, attrs, model)

          if dry_run
            raise ActiveRecord::RecordInvalid, record unless record.valid?
          else
            record.save!
          end
          is_new ? (result.created += 1) : (result.updated += 1)
        rescue StandardError => error
          # Store ONLY the row number + message — NEVER the raw cell values. The
          # result is persisted (OpenLoam::ProgressJob.result); a failed row into an
          # encrypted field would otherwise write PLAINTEXT PII at rest.
          result.failed += 1
          result.errors << { "row" => line, "message" => error.message }
        end
        progress&.advance
      end

      result
    end

    # The failed rows as a fix-and-re-upload CSV — rebuilt from the ORIGINAL csv
    # (a transient download the user already holds), NOT from the persisted
    # result (which carries no cell values). Each cell is neutralized against CSV
    # formula injection.
    def error_csv(result, csv_string)
      rows = safe_parse(csv_string)
      headers = rows.first || []
      data_rows = rows.drop(1)

      CSV.generate do |out|
        out << (Array(headers) + [ "_error" ])
        result.errors.each do |error|
          original = data_rows[error["row"] - 2] || [] # row is 1-based incl. the header
          out << original.map { |cell| OpenLoam::Csv.safe(cell) } + [ error["message"] ]
        end
      end
    end

    # ---- internals ----

    def refuse_bad_mapping!(mapping, allowed)
      mapping.each_value do |target|
        next if target.to_s.blank?
        next if allowed.include?(target.to_s)

        raise OpenLoam::Error, "import mapping refuses #{target.inspect} — not a writable column or custom field"
      end
    end

    def row_attributes(headers, row, mapping)
      cells = Hash[headers.zip(row)]
      mapping.each_with_object({}) do |(header, target), attrs|
        next if target.to_s.blank?

        attrs[target.to_s] = cells[header]
      end
    end

    def find_or_build(model, attrs, match_key)
      key = match_key.to_s
      if key.present? && attrs[key].present?
        # find_by is tenant-scoped, so update-by-key can only ever hit a record
        # in the CURRENT tenant.
        existing = model.find_by(key => attrs[key])
        return [ existing, false ] if existing
      end
      [ model.new, true ]
    end

    def assign(record, attrs, model)
      columns = model.column_names.to_set
      customs = model.respond_to?(:custom_field_definitions) ? model.custom_field_definitions.map(&:name).to_set : Set.new

      attrs.each do |field, value|
        if columns.include?(field)
          record.public_send("#{field}=", value)
        elsif customs.include?(field)
          record.set_custom_field(field, value)
        end
      end
    end

    def safe_parse(csv_string)
      CSV.parse(csv_string.to_s)
    rescue CSV::MalformedCSVError => error
      raise OpenLoam::Error, "could not parse CSV: #{error.message}"
    end

    def policy_for(model, actor)
      klass = "#{model.name}Policy".safe_constantize
      # A blank instance as the record: readable?/writable? key off the role, but
      # custom_field_writable? reads record.class.custom_field_definitions.
      (klass || OpenLoam::Policy).new(actor, model.new)
    end
  end
end
