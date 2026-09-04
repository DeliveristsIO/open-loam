module OpenLoam
  # A per-tenant, admin-configurable rule: WHEN a condition holds THEN run
  # actions. Declared as DATA (a trigger event pattern + a safe condition tree +
  # a typed action list), never as code — see OpenLoam::BusinessRules for the engine
  # that evaluates it. Audited like any business record.
  class BusinessRule < OpenLoam::TenantRecord
    self.table_name = "open_loam_business_rules"

    include OpenLoam::Auditable

    has_many :runs, class_name: "OpenLoam::BusinessRuleRun", dependent: :delete_all

    validates :name, :trigger, presence: true
    # A rule may only target a tenant-scoped model (or none, for an event-only
    # rule). Refusing a global class like `User` at SAVE time means a poisoned
    # rule can't even be persisted — kept in lockstep with
    # OpenLoam::BusinessRules.subject_for, which refuses the same at run time.
    validate :entity_type_targets_a_tenant_record

    scope :active, -> { where(active: true) }
    scope :by_priority, -> { order(priority: :desc, id: :asc) }
    scope :for_entity, ->(entity_type) { where(entity_type: entity_type.to_s) }

    def matches_trigger?(event_name)
      OpenLoam::Events.pattern_matches?(trigger, event_name)
    end

    # The stored json, defensively — a hand-created row could hold a non-hash /
    # non-array.
    def condition_tree
      condition.is_a?(Hash) ? condition : {}
    end

    def action_list
      actions.is_a?(Array) ? actions : []
    end

    private

    def entity_type_targets_a_tenant_record
      return if entity_type.blank?  # event-only rule, no subject to load

      klass = entity_type.safe_constantize
      unless klass.is_a?(Class) && klass < OpenLoam::TenantRecord
        errors.add(:entity_type, "must name a OpenLoam tenant-scoped model (not #{entity_type.inspect})")
      end
    end
  end
end
