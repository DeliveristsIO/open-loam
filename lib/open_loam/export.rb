require "csv"

module OpenLoam
  # CSV export of a tenant-scoped relation, POLICY- and ENCRYPTION-aware:
  #
  #   OpenLoam::Export.csv(Equipment.all, actor: current_actor)
  #
  # * only fields the actor's role may READ are columns (OpenLoam::Policy#readable?);
  # * an ENCRYPTED column is NEVER exported in the clear — its cell is
  #   "[encrypted]" (the same redaction as the audit trail), so a bulk export can
  #   never become a plaintext dump of PII a role shouldn't see;
  # * declared custom fields are included (a dictionary field exports its stored
  #   code, so the file round-trips back through OpenLoam::Import);
  # * tenant isolation is free — the relation is already scoped.
  #
  # Prototype scale: builds the CSV in memory with the stdlib CSV. A very large
  # export would stream row-by-row through an enumerator body — the same column
  # logic, a different sink.
  module Export
    REDACTED = "[encrypted]".freeze
    # Never exported: tenant plumbing and optimistic-locking bookkeeping.
    SKIP_COLUMNS = %w[tenant_id lock_version deleted_at].freeze

    module_function

    def csv(scope, actor:)
      model = scope.klass
      columns = exportable_columns(model, actor)

      CSV.generate do |out|
        out << columns.map { |c| c[:header] }
        scope.find_each { |record| out << columns.map { |c| cell(record, c) } }
      end
    end

    # The ordered column spec: readable real columns (encrypted ones kept but
    # redacted), then declared custom fields.
    def exportable_columns(model, actor)
      policy = policy_for(model, actor)
      encrypted = model.respond_to?(:open_loam_encrypted_attributes) ? model.open_loam_encrypted_attributes : []
      # The blind-index columns behind searchable encrypted fields (e.g.
      # email_hash) are internal HMACs — never export them either.
      blind = model.respond_to?(:open_loam_searchable_encrypted_attributes) ? model.open_loam_searchable_encrypted_attributes.map { |a| "#{a}_hash" } : []

      columns = model.column_names.reject { |c| SKIP_COLUMNS.include?(c) || blind.include?(c) || c == "custom_fields" }
                     .select { |c| policy.readable?(c) }
                     .map { |c| { header: c, name: c, kind: encrypted.include?(c) ? :encrypted : :column } }

      if model.respond_to?(:custom_field_definitions)
        model.custom_field_definitions.order(:name).each do |definition|
          columns << { header: definition.name, name: definition.name, kind: :custom }
        end
      end

      columns
    end

    def cell(record, column)
      value = case column[:kind]
              when :encrypted then REDACTED
              when :custom    then (record.custom_field(column[:name]) rescue nil)
              else record.public_send(column[:name])
              end
      OpenLoam::Csv.safe(value) # neutralize CSV formula injection (=, +, -, @, tab/CR)
    end

    def policy_for(model, actor)
      klass = "#{model.name}Policy".safe_constantize
      # A blank instance as the record: readable? keys off the role, but the
      # policy's custom-field checks read record.class.
      (klass || OpenLoam::Policy).new(actor, model.new)
    end
  end
end
