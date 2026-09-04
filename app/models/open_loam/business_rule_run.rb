module Loam
  # The log of why a business rule did (or did not) act — so the admin can see
  # WHY something happened. Plumbing, like Loam::RecordLock: NOT audited (a log
  # of a log is noise). Capped per rule so the table stays lean.
  class BusinessRuleRun < Loam::TenantRecord
    self.table_name = "loam_business_rule_runs"

    KEEP_PER_RULE = 50

    belongs_to :business_rule, class_name: "Loam::BusinessRule"

    scope :recent, -> { order(created_at: :desc) }

    after_create_commit :prune_old_runs

    private

    # Keep the last KEEP_PER_RULE runs per rule; drop the rest. Cheap and bounded.
    def prune_old_runs
      stale = self.class.where(business_rule_id: business_rule_id)
                        .order(created_at: :desc)
                        .offset(KEEP_PER_RULE)
                        .ids
      self.class.where(id: stale).delete_all if stale.any?
    end
  end
end
