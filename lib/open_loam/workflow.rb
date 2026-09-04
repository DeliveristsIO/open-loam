module OpenLoam
  # Declarative state machine for a tenant-scoped entity: the states a record
  # can be in, the legal moves between them, and who may make each move.
  #
  #   class PurchaseOrder < OpenLoam::TenantRecord
  #     include OpenLoam::Workflow
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
  #   PurchaseOrder.open_loam_workflow           # the frozen definition, for agents and admin UI
  #
  # What this buys over hand-rolled `if status == "draft"`: an illegal move
  # raises instead of silently writing a bad value, the roles that may move a
  # record are declared in one readable place instead of scattered across
  # controllers, and the whole machine is introspectable.
  #
  # The state change itself is an ordinary attribute write, so OpenLoam::Auditable
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
      class_attribute :open_loam_workflow, instance_writer: false, default: nil

      # THE gate: the workflow column may only change through a transition
      # (open_loam_perform_transition!), which enforces from-state and role. A direct
      # write — the edit form, Bulk.set_field, an import, a business-rule
      # set_field — would otherwise let a member self-"approve", skipping the
      # transition's roles:. Closing it here closes ALL paths at once. Creation
      # (the initial state) is exempt (`on: :update`).
      validate :open_loam_workflow_column_only_via_transition, on: :update
    end

    class_methods do
      # The DSL. `initial:` defaults to the first declared state.
      def workflow(column, initial: nil, &block)
        definition = Builder.new(column, initial).build(&block)
        self.open_loam_workflow = definition

        before_validation on: :create do
          self[definition.column] = definition.initial if self[definition.column].blank?
        end

        # A workflow column may only ever hold a declared state, whoever writes
        # it — a transition, a form, a console.
        validates definition.column,
                  inclusion: { in: definition.states, message: "is not one of: #{definition.states.join(', ')}" }

        include open_loam_workflow_module(definition)
      end

      # Transition and predicate methods live in their own module rather than
      # on the class, so an app can override `submit!` and still call `super`.
      def open_loam_workflow_module(definition)
        model = self

        Module.new do
          definition.transitions.each_value do |transition|
            define_method("#{transition.name}!") { open_loam_perform_transition!(transition) }
          end

          definition.states.each do |state|
            predicate = "#{state}?"
            next unless model.open_loam_workflow_predicate_free?(predicate)

            # A state predicate must never shadow a real column: DamageReport
            # has both a workflow state "approved" and an `approved` boolean
            # column, and `record.approved?` has to stay the column's. The
            # column check happens at CALL time, not class-load time — at load
            # the schema may not be readable yet (fresh CI database, db:create),
            # and a load-time decision made OpenLoam behave differently on CI than
            # on a warmed-up dev machine.
            define_method(predicate) do
              if self.class.columns_hash.key?(state)
                query_attribute(state)
              else
                self[definition.column].to_s == state
              end
            end
          end
        end
      end

      # Explicitly defined methods still win — only truly free names get a
      # workflow predicate. Column collisions are handled inside the predicate
      # itself (see open_loam_workflow_module), where the schema is reliably known.
      def open_loam_workflow_predicate_free?(predicate)
        !method_defined?(predicate) && !private_method_defined?(predicate)
      end
    end

    # Transition names that are legal right now: from this record's state, for
    # the actor in OpenLoam::Current. Never raises — an admin screen asks this to
    # decide which buttons to render.
    def workflow_transitions_available
      role = open_loam_workflow_role

      self.class.open_loam_workflow.transitions_from(open_loam_workflow_state)
          .select { |transition| transition.roles.empty? || transition.roles.include?(role) }
          .map(&:name)
    end

    def open_loam_workflow_state
      self[self.class.open_loam_workflow.column].to_s
    end

    private

    def open_loam_workflow_column_only_via_transition
      return unless self.class.open_loam_workflow

      column = self.class.open_loam_workflow.column
      return unless attribute_changed?(column)
      return if @open_loam_in_transition

      errors.add(column, "can only change through a workflow transition, not a direct write")
    end

    def open_loam_perform_transition!(transition)
      from = open_loam_workflow_state

      unless transition.from.include?(from)
        raise InvalidTransitionError,
              "#{self.class.name}##{transition.name}! moves #{transition.from.join('/')} -> #{transition.to}, " \
              "but this record is #{from.inspect}"
      end

      open_loam_authorize_transition!(transition)

      self[self.class.open_loam_workflow.column] = transition.to
      begin
        @open_loam_in_transition = true # tells the guard THIS column change is blessed
        save!
      ensure
        @open_loam_in_transition = false
      end

      OpenLoam::Events.publish(
        "#{open_loam_workflow_event_domain}.#{model_name.param_key}.#{transition.name}",
        id: id, from: from, to: transition.to
      )

      self
    end

    def open_loam_authorize_transition!(transition)
      return if transition.roles.empty?

      allowed = transition.roles.join(", ")
      unless OpenLoam::Current.actor
        raise NotAuthorizedError,
              "#{self.class.name}##{transition.name}! is restricted to #{allowed}, but there is no actor in " \
              "OpenLoam::Current — wrap the call in OpenLoam.as_tenant(tenant, actor: user) { ... }"
      end

      return if transition.roles.include?(open_loam_workflow_role)

      raise NotAuthorizedError,
            "#{self.class.name}##{transition.name}! is restricted to #{allowed}; " \
            "this actor's role is #{open_loam_workflow_role.inspect}"
    end

    # Role resolution deliberately goes through OpenLoam::Policy: "your role" means
    # exactly one thing — your membership role in the current tenant — here, in
    # policies, and in the admin.
    def open_loam_workflow_role
      actor = OpenLoam::Current.actor
      actor && OpenLoam::Policy.new(actor, self).role
    end

    # Transitions publish into the model's own event domain when it has one
    # (OpenLoam::Eventful), so workflow events sit beside the lifecycle events.
    def open_loam_workflow_event_domain
      self.class.respond_to?(:open_loam_event_domain) ? self.class.open_loam_event_domain : "app"
    end
  end
end
