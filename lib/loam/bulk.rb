module Loam
  # Datatable bulk actions over selected records — policy-checked PER record and
  # tenant-scoped. The ids are resolved THROUGH the tenant scope
  # (`model.where(id: ids)`), so a forged cross-tenant id is simply not found —
  # a bulk op can never reach another tenant's rows.
  #
  #   Loam::Bulk.soft_delete(Equipment, params[:ids])
  #   Loam::Bulk.set_field(Equipment, params[:ids], field: "status", value: "retired")
  #
  # Returns the number of records actually affected (a record the actor may not
  # touch, or an id from another tenant, is silently skipped).
  module Bulk
    module_function

    def soft_delete(model, ids)
      each_permitted(model, ids) do |record, policy|
        next unless policy.destroy?

        record.soft_delete!
        true
      end
    end

    def set_field(model, ids, field:, value:)
      field = field.to_s
      each_permitted(model, ids) do |record, policy|
        next unless policy.update? && policy.writable?(field) && writable_column?(model, field)

        record.update!(field => value)
        true
      end
    end

    # A relation for "export selected" — tenant-scoped, so it composes with
    # Loam::Export.csv and can't leak another tenant's rows.
    def selected(model, ids)
      model.where(id: Array(ids))
    end

    def each_permitted(model, ids)
      count = 0
      selected(model, ids).find_each do |record|
        count += 1 if yield(record, Loam::Policy.for(record))
      end
      count
    end

    def writable_column?(model, field)
      model.column_names.include?(field) && Loam::Import::PLUMBING.exclude?(field)
    end
  end
end
