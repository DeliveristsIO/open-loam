module Loam
  module BusinessRules
    # The typed action vocabulary — a FIXED, safe set the engine dispatches. No
    # arbitrary code: an action is a json descriptor with a `type` and known
    # keys. `call_webhook` is deferred (emit_event → a webhook endpoint already
    # covers it).
    module Actions
      PLUMBING = %w[id tenant_id lock_version deleted_at created_at updated_at].freeze

      # Run one action against the record that triggered the rule. Returns a
      # short label of what it did (for the execution log). `:veto` is the
      # block_transition signal (see Loam::BusinessRules.veto?).
      def self.run(action, record)
        case action["type"].to_s
        when "notify"           then run_notify(action, record)
        when "emit_event"       then run_emit_event(action)
        when "set_field"        then run_set_field(action, record)
        when "block_transition" then :veto
        else raise ArgumentError, "unknown action type #{action["type"].inspect}"
        end
      end

      def self.run_notify(action, _record)
        title = action["title"].to_s
        body = action["body"]
        if action["role"].present?
          Loam::Notifications.notify_role(action["role"], title: title, body: body)
        elsif action["user_id"].present?
          user = User.find_by(id: action["user_id"])
          Loam::Notifications.notify(user, title: title, body: body) if user
        end
        "notify"
      end

      # Publish validates the name format (raising InvalidEventNameError), so a
      # malformed event name is caught by the engine's per-rule isolation.
      def self.run_emit_event(action)
        Loam::Events.publish(action["name"], (action["payload"] || {}).symbolize_keys)
        "emit_event(#{action["name"]})"
      end

      # Assign a whitelisted attribute or custom field on the TRIGGERING record.
      # Refused: the workflow status column (would bypass the transition gate —
      # use a transition), and plumbing columns. The change is saved as the
      # event's actor, and the rule is identifiable via the execution log.
      def self.run_set_field(action, record)
        field = action["field"].to_s
        refuse_workflow_column!(record, field)

        if writable_column?(record.class, field)
          record.update!(field => action["value"])
        elsif Condition.custom_field?(record, field)
          record.set_custom_field(field, action["value"])
          record.save!
        else
          raise ArgumentError, "set_field: #{field.inspect} is not a writable column or custom field"
        end
        "set_field(#{field})"
      end

      def self.writable_column?(klass, field)
        klass.column_names.include?(field) && PLUMBING.exclude?(field)
      end

      def self.refuse_workflow_column!(record, field)
        return unless record.class.respond_to?(:loam_workflow) && record.class.loam_workflow&.column == field

        raise ArgumentError, "set_field must not write the workflow column #{field.inspect} — use a transition"
      end
    end
  end
end
