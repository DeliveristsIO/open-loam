module OpenLoam
  # Response enrichers: one module attaches a computed block onto ANOTHER
  # module's entity in admin/API responses, with no foreign-key coupling.
  #
  #   # billing knows about equipment; equipment knows nothing about billing:
  #   OpenLoam::Enrichers.register("Equipment", key: "outstanding_balance") do |equipment|
  #     Invoice.where(equipment_id: equipment.id).sum(:balance)
  #   end
  #
  #   OpenLoam::Enrichers.enrich(equipment)        # => { "outstanding_balance" => 1200 }
  #   OpenLoam::Enrichers.enrich_many(equipments)  # => { id => { key => value }, ... }
  #
  # Distinct from custom fields: a custom field is STORED on the record; an
  # enricher is COMPUTED at read time by different (possibly cross-module) code.
  #
  # BATCH to avoid N+1: pass `batch:` (an array -> { record.id => value }) and
  # `enrich_many` resolves N records in one query instead of N. `enrich` reuses
  # the batch path for a single record, so batched enrichers are cheap either way.
  #
  # Enrichers run in the CURRENT tenant context (the record was loaded there), so
  # a resolver querying tenant-scoped models can only ever see this tenant's data.
  # A resolver that raises is ISOLATED — its key is omitted, the rest still
  # resolve, and the response is never broken. (No timeout in the prototype — a
  # pathologically slow enricher is a future concern.)
  module Enrichers
    Enricher = Struct.new(:entity_type, :key, :priority, :resolver, :batch_resolver, keyword_init: true)

    class << self
      # Register an enricher for records of `entity_type` (the model's base-class
      # name, e.g. "Equipment"). Provide a per-record block OR a `batch:` proc.
      def register(entity_type, key:, priority: 0, batch: nil, &resolver)
        raise ArgumentError, "register needs a block or a batch: resolver" unless resolver || batch

        registry[entity_type.to_s] << Enricher.new(
          entity_type: entity_type.to_s, key: key.to_s, priority: priority,
          resolver: resolver, batch_resolver: batch
        )
      end

      def enrich(record)
        enrich_many([record]).fetch(record.id, {})
      end

      # { record.id => { key => value } } for a homogeneous array of records.
      def enrich_many(records)
        records = Array(records)
        return {} if records.empty?

        types = records.map { |record| record.class.base_class }.uniq
        raise ArgumentError, "enrich_many expects one entity type, got #{types.map(&:name).join(', ')}" if types.size > 1

        by_id = records.each_with_object({}) { |record, hash| hash[record.id] = {} }

        for_type(types.first).each do |enricher|
          # Per-enricher isolation: a raise omits THIS key for all records; the
          # others still resolve.
          begin
            if enricher.batch_resolver
              values = enricher.batch_resolver.call(records)
              records.each { |record| by_id[record.id][enricher.key] = values[record.id] }
            else
              records.each { |record| by_id[record.id][enricher.key] = enricher.resolver.call(record) }
            end
          rescue StandardError => error
            warn_failure(enricher, error)
          end
        end

        by_id
      end

      # --- test support: the registry is process-global, so a test snapshots it
      # in setup and restores in teardown (keeping the app's boot-registered
      # enrichers intact, which `clear!` would not).
      def snapshot
        registry.transform_values(&:dup)
      end

      def restore(snapshot)
        @registry = Hash.new { |hash, key| hash[key] = [] }
        snapshot.each { |type, enrichers| @registry[type] = enrichers.dup }
      end

      private

      def registry
        @registry ||= Hash.new { |hash, key| hash[key] = [] }
      end

      # The enrichers for a class. Distinct keys compose; if two register the
      # SAME key, higher priority wins, ties go to the later registration.
      def for_type(klass)
        registry[klass.base_class.name]
          .group_by(&:key)
          .map { |_key, group| group.each_with_index.max_by { |enricher, index| [enricher.priority, index] }.first }
      end

      def warn_failure(enricher, error)
        Rails.logger&.warn(
          "[OpenLoam::Enrichers] #{enricher.entity_type}/#{enricher.key} raised #{error.class}: #{error.message} — key omitted"
        )
      end
    end
  end
end
