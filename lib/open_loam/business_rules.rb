require "open_loam/business_rules/condition"
require "open_loam/business_rules/actions"

module OpenLoam
  # The engine that evaluates OpenLoam::BusinessRule rows: WHEN a trigger fires and
  # the condition holds, THEN run the actions — in the event's tenant context,
  # in priority order, each rule isolated so one failure never breaks dispatch.
  #
  # It listens to every OpenLoam event (like OpenLoam::Webhooks), so a tenant can add a
  # rule from the admin without a reboot. Evaluation runs INLINE in whatever
  # published the event — cheap for the prototype; a job-based dispatcher is the
  # scaling path.
  module BusinessRules
    MAX_DEPTH = 3 # bounds a rule chain: an emit_event action can trigger more
                  # rules, but only so deep, so a self-triggering rule terminates.

    class << self
      # Wired once from OpenLoam::Engine. Idempotent — subscribing twice would run
      # every rule twice (see OpenLoam::Webhooks.subscribe!).
      def subscribe!
        @subscription ||= OpenLoam::Events.subscribe_all { |event_name, payload| on_event(event_name, payload) }
      end

      def on_event(event_name, payload)
        tenant = OpenLoam::Tenant.find_by(id: payload[:tenant_id])
        return if tenant.nil?

        OpenLoam.as_tenant(tenant) do
          within_depth_guard do
            OpenLoam::BusinessRule.active.by_priority.each do |rule|
              next unless rule.matches_trigger?(event_name)

              run_rule(rule, subject_for(rule, payload), event_name)
            end
          end
        end
      end

      # Manual evaluation for a record — for programmatic/test use. Runs the
      # active rules for the record's entity type (optionally filtered to a
      # trigger) in priority order.
      def evaluate(record, trigger: nil)
        OpenLoam::BusinessRule.active.for_entity(record.class.base_class.name).by_priority.each do |rule|
          next if trigger && !rule.matches_trigger?(trigger)

          run_rule(rule, record, trigger)
        end
      end

      # Do the active rules with a block_transition action, whose condition
      # holds, veto this transition? Consulted by a workflow BEFORE it moves (see
      # the demo's DamageReport). Evaluate-only — no actions run, nothing logged.
      def veto?(record, trigger)
        OpenLoam::BusinessRule.active.for_entity(record.class.base_class.name).by_priority.any? do |rule|
          rule.matches_trigger?(trigger) &&
            rule.action_list.any? { |action| action["type"].to_s == "block_transition" } &&
            Condition.matches?(rule.condition_tree, record)
        end
      end

      private

      def run_rule(rule, record, event_name)
        if record.nil? && rule.entity_type.present?
          return log(rule, nil, event_name, matched: false, error: "subject not found")
        end

        matched = Condition.matches?(rule.condition_tree, record)
        taken = []
        # block_transition is a veto signal consumed elsewhere, not an action to
        # perform here, so it is skipped in the THEN path.
        rule.action_list.each { |action| taken << Actions.run(action, record) } if matched && record

        log(rule, record, event_name, matched: matched, actions_taken: taken.compact) if matched || taken.any?
      rescue StandardError => error
        log(rule, record, event_name, matched: false, error: error.message)
      end

      def log(rule, record, event_name, matched:, actions_taken: [], error: nil)
        # Lean: log the runs that ACTED, errored, or found no subject — not the
        # deterministic "condition didn't match" ones (readable from the rule).
        return if !matched && error.nil?

        OpenLoam::BusinessRuleRun.create!(
          business_rule: rule,
          subject_type: record&.class&.base_class&.name,
          subject_id: record&.id,
          event_name: event_name,
          matched: matched,
          actions_taken: actions_taken,
          error: error
        )
      end

      # A rule watches a specific entity; load THAT record from the rule's
      # entity_type + the event's id (find_by, not find — a record deleted
      # between publish and dispatch is a missing subject, not a crash).
      def subject_for(rule, payload)
        return nil if rule.entity_type.blank? || payload[:id].blank?

        klass = rule.entity_type.safe_constantize
        # A rule may ONLY target a tenant-scoped model. This is the security
        # boundary: a global model like `User` has no tenant default scope, so a
        # find_by(id:) would reach across tenants — refusing anything that is not
        # a OpenLoam::TenantRecord closes that, and a TenantRecord.find_by can only
        # ever return a record in the CURRENT tenant even if an id is injected.
        return nil unless klass.is_a?(Class) && klass < OpenLoam::TenantRecord

        klass.find_by(id: payload[:id])
      end

      def within_depth_guard
        depth = Thread.current[:open_loam_rule_depth] ||= 0
        return if depth >= MAX_DEPTH

        Thread.current[:open_loam_rule_depth] = depth + 1
        yield
      ensure
        Thread.current[:open_loam_rule_depth] = depth if depth
      end
    end
  end
end
