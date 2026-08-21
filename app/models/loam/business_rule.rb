module Loam
  # A per-tenant, admin-configurable rule: WHEN a condition holds THEN run
  # actions. Declared as DATA (a trigger event pattern + a safe condition tree +
  # a typed action list), never as code — see Loam::BusinessRules for the engine
  # that evaluates it. Audited like any business record.
  class BusinessRule < Loam::TenantRecord
    self.table_name = "loam_business_rules"

    include Loam::Auditable

    has_many :runs, class_name: "Loam::BusinessRuleRun", dependent: :delete_all

    validates :name, :trigger, presence: true

    scope :active, -> { where(active: true) }
    scope :by_priority, -> { order(priority: :desc, id: :asc) }
    scope :for_entity, ->(entity_type) { where(entity_type: entity_type.to_s) }

    def matches_trigger?(event_name)
      Loam::Events.pattern_matches?(trigger, event_name)
    end

    # The stored json, defensively — a hand-created row could hold a non-hash /
    # non-array.
    def condition_tree
      condition.is_a?(Hash) ? condition : {}
    end

    def action_list
      actions.is_a?(Array) ? actions : []
    end
  end
end
