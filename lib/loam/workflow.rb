module Loam
  # Declarative state machine for a tenant-scoped entity: the states a record
  # can be in, the legal moves between them, and who may make each move.
  #
  #   class PurchaseOrder < Loam::TenantRecord
  #     include Loam::Workflow
  #
  #     workflow :status, initial: "draft" do
  #       state "draft"
  #       state "pending_approval"
  #       state "approved"
  #
  #       transition :submit,  from: "draft",            to: "pending_approval"
  #       transition :approve, from: "pending_approval", to: "approved", roles: [:manager]
  #     end
  #   end
  #
  #   order.submit!                         # draft -> pending_approval, publishes
  #                                         # "<domain>.purchase_order.submit"
  #   order.workflow_transitions_available  # => [:approve] for a manager, [] for anyone else
  #   PurchaseOrder.loam_workflow           # the frozen definition, for agents and admin UI
  #
  # What this buys over hand-rolled `if status == "draft"`: an illegal move
  # raises instead of silently writing a bad value, the roles that may move a
  # record are declared in one readable place instead of scattered across
  # controllers, and the whole machine is introspectable.
  #
  # The state change itself is an ordinary attribute write, so Loam::Auditable
  # records it like any other change — a workflow adds no second audit trail.
  module Workflow
    extend ActiveSupport::Concern

    # One declared move. `from` is a list because several states may share a
    # move (e.g. cancel from draft OR pending_approval); `roles` empty means
    # "not role-gated here" — the policy layer still gates the controller.
    Transition = Struct.new(:name, :from, :to, :roles, keyword_init: true)

    # The whole machine, frozen at class-definition time.
    Definition = Struct.new(:column, :initial, :states, :transitions, keyword_init: true) do
      def transitions_from(state)
        transitions.each_value.select { |transition| transition.from.include?(state.to_s) }
      end
    end

    # Collects the DSL block and validates the machine as a whole before
    # freezing it. Validation runs at the end, so `state` and `transition` may
    # appear in any order inside the block.
    class Builder
      def initialize(column, initial)
        @column = column.to_s
        @initial = initial&.to_s
        @states = []
        @transitions = {}
      end

      def state(name)
        @states << name.to_s
      end

      def transition(name, from:, to:, roles: [])
        @transitions[name.to_sym] = Transition.new(
          name: name.to_sym,
          from: Array(from).map(&:to_s).freeze,
          to: to.to_s,
          roles: Array(roles).map(&:to_sym).freeze
        ).freeze
      end

      def build(&block)
        instance_eval(&block)
        validate!

        Definition.new(
          column: @column,
          initial: @initial || @states.first,
          states: @states.freeze,
          transitions: @transitions.freeze
        ).freeze
      end

      private

      # A typo in a state name is a bug that would otherwise surface much
      # later, as a transition that can never fire. Fail at class load.
      def validate!
        raise Error, "workflow #{@column} declares no states" if @states.empty?

        undeclared = @transitions.each_value.flat_map { |t| t.from + [t.to] }.uniq - @states
        if undeclared.any?
          raise Error, "workflow #{@column} moves to/from undeclared states: #{undeclared.join(', ')} " \
                       "(declare each one with `state \"name\"`)"
        end

        return if @initial.nil? || @states.include?(@initial)

        raise Error, "workflow #{@column} initial state #{@initial.inspect} is not a declared state"
      end
    end

    included do
      # nil until `workflow` is called; inherited by subclasses.
      class_attribute :loam_workflow, instance_writer: false, default: nil
    end

    class_methods do
      # The DSL. `initial:` defaults to the first declared state.
      def workflow(column, initial: nil, &block)
        definition = Builder.new(column, initial).build(&block)
        self.loam_workflow = definition

        before_validation on: :create do
          self[definition.column] = definition.initial if self[definition.column].blank?
        end

        # A workflow column may only ever hold a declared state, whoever writes
        # it — a transition, a form, a console.
        validates definition.column,
                  inclusion: { in: definition.states, message: "is not one of: #{definition.states.join(', ')}" }

        include loam_workflow_module(definition)
      end

      # Transition and predicate methods live in their own module rather than
      # on the class, so an app can override `submit!` and still call `super`.
      def loam_workflow_module(definition)
        model = self

        Module.new do
          definition.transitions.each_value do |transition|
            define_method("#{transition.name}!") { loam_perform_transition!(transition) }
          end

          definition.states.each do |state|
            predicate = "#{state}?"
            next unless model.loam_workflow_predicate_free?(predicate, state)

            define_method(predicate) { self[definition.column].to_s == state }
          end
        end
      end

      # A state predicate must never shadow a real column or an existing
      # method: DamageReport has both a workflow state "approved" and an
      # `approved` boolean column, and `record.approved?` has to stay the
      # column's. When the schema cannot be read (no database yet, e.g. during
      # db:create) we assume a conflict — a missing convenience predicate is
      # harmless, a predicate hiding a column is not.
      def loam_workflow_predicate_free?(predicate, state)
        return false if method_defined?(predicate) || private_method_defined?(predicate)

        known_columns = begin
          table_exists? ? column_names : []
        rescue ActiveRecord::ActiveRecordError
          nil
        end

        !known_columns.nil? && !known_columns.include?(state)
      end
    end

    # Transition names that are legal right now: from this record's state, for
    # the actor in Loam::Current. Never raises — an admin screen asks this to
    # decide which buttons to render.
    def workflow_transitions_available
      role = loam_workflow_role

      self.class.loam_workflow.transitions_from(loam_workflow_state)
          .select { |transition| transition.roles.empty? || transition.roles.include?(role) }
          .map(&:name)
    end

    def loam_workflow_state
      self[self.class.loam_workflow.column].to_s
    end

    private

    def loam_perform_transition!(transition)
      from = loam_workflow_state

      unless transition.from.include?(from)
        raise InvalidTransitionError,
              "#{self.class.name}##{transition.name}! moves #{transition.from.join('/')} -> #{transition.to}, " \
              "but this record is #{from.inspect}"
      end

      loam_authorize_transition!(transition)

      self[self.class.loam_workflow.column] = transition.to
      save!

      Loam::Events.publish(
        "#{loam_workflow_event_domain}.#{model_name.param_key}.#{transition.name}",
        id: id, from: from, to: transition.to
      )

      self
    end

    def loam_authorize_transition!(transition)
      return if transition.roles.empty?

      allowed = transition.roles.join(", ")
      unless Loam::Current.actor
        raise NotAuthorizedError,
              "#{self.class.name}##{transition.name}! is restricted to #{allowed}, but there is no actor in " \
              "Loam::Current — wrap the call in Loam.as_tenant(tenant, actor: user) { ... }"
      end

      return if transition.roles.include?(loam_workflow_role)

      raise NotAuthorizedError,
            "#{self.class.name}##{transition.name}! is restricted to #{allowed}; " \
            "this actor's role is #{loam_workflow_role.inspect}"
    end

    # Role resolution deliberately goes through Loam::Policy: "your role" means
    # exactly one thing — your membership role in the current tenant — here, in
    # policies, and in the admin.
    def loam_workflow_role
      actor = Loam::Current.actor
      actor && Loam::Policy.new(actor, self).role
    end

    # Transitions publish into the model's own event domain when it has one
    # (Loam::Eventful), so workflow events sit beside the lifecycle events.
    def loam_workflow_event_domain
      self.class.respond_to?(:loam_event_domain) ? self.class.loam_event_domain : "app"
    end
  end
end
