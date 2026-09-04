module OpenLoam
  # A staged mutation awaiting human approval. When a caller runs under
  # confirm-mode (an MCP tool acting for an AI agent — see OpenLoam.mutation_mode), a
  # write is staged HERE as a preview instead of committing; a manager approves
  # or rejects, and only approval executes it. This is OpenLoam's thesis made
  # concrete: agent-triggered writes are gate-able.
  #
  # The approval gate IS a workflow (OpenLoam::Workflow): pending → (manager) approve
  # / reject → executed / failed. "Who may approve" lives in one declarative,
  # role-gated place. The proposed changes are encrypted at rest (OpenLoam::Encryptable),
  # because a staged change to an encrypted target field would otherwise sit here
  # — and in this row's own audit — as plaintext, reopening the leak L-901 closed.
  class PendingAction < OpenLoam::TenantRecord
    self.table_name = "open_loam_pending_actions"

    include OpenLoam::Auditable
    include OpenLoam::Encryptable
    include OpenLoam::Workflow

    belongs_to :actor, class_name: "User", optional: true
    belongs_to :reviewer, class_name: "User", foreign_key: :reviewed_by_id, optional: true

    # Encrypted JSON. Encryptable also makes Auditable redact `changeset` to
    # "[encrypted]" automatically, so the proposal never lands in the audit trail.
    encrypts :changeset

    validates :action_type, :summary, :idempotency_key, presence: true
    # Only ONE pending row per proposal per tenant — a rejected/executed row with
    # the same key may coexist so the proposal can be re-staged later. `conditions`
    # scopes the existence check to pending rows (so a rejected row does not block
    # a re-stage); `if: :pending?` skips the check on a non-pending row's own saves.
    # Both mirror the partial DB index (WHERE status = 'pending').
    validates :idempotency_key,
              uniqueness: { scope: :tenant_id, conditions: -> { where(status: "pending") } },
              if: :pending?

    # The review queue: still awaiting a decision.
    scope :pending, -> { where(status: "pending") }

    # status is a workflow column, but a plain column underneath — guard it so a
    # direct `update!(status: "executed")` cannot skip the manager role gate and
    # execute_change!. Only a `to_*` transition (which sets the flag below) may
    # move it. `update_column` / raw SQL remain the deliberate low-level escape
    # hatch, like `.unscoped`.
    validate :status_changes_only_through_a_transition, on: :update
    # ...and a new row must START pending — otherwise create!(status: "executed")
    # would forge an already-approved/executed record without any transition.
    validate :status_starts_at_the_initial_state, on: :create

    # Transitions are prefixed `to_` so their generated bang methods do not
    # collide with the public approve!/reject!(by:) API below.
    workflow :status, initial: "pending" do
      state "pending"
      state "approved"
      state "rejected"
      state "executed"
      state "failed"

      transition :to_approved, from: "pending",  to: "approved", roles: [ :manager ]
      transition :to_rejected, from: "pending",  to: "rejected", roles: [ :manager ]
      transition :to_executed, from: "approved", to: "executed"
      transition :to_failed,   from: "approved", to: "failed"
    end

    # `changeset` is a Hash in Ruby but an encrypted JSON string at rest. The
    # class methods win over Encryptable's included module and reach it via super.
    def changeset
      raw = super
      raw.present? ? JSON.parse(raw) : {}
    end

    def changeset=(value)
      super(value.nil? ? nil : value.to_json)
    end

    # A structured before/after diff. An encrypted target field shows
    # "[encrypted]" on BOTH sides — a reviewer sees THAT a secret changes, never
    # its value.
    def preview
      target = load_target
      encrypted = encrypted_target_fields

      changeset.each_with_object({}) do |(field, proposed), diff|
        field = field.to_s
        diff[field] =
          if encrypted.include?(field)
            { "from" => (target ? "[encrypted]" : nil), "to" => "[encrypted]" }
          else
            { "from" => target&.read_attribute(field), "to" => proposed }
          end
      end
    end

    # Approve and execute, atomically enough: the transition is role-gated to a
    # manager; execution runs in a transaction so a failure leaves NO partial
    # write; the record ends "executed" or "failed". Executes as `by`, so the
    # TARGET's audit names the approving human — the person owns the change.
    def approve!(by:)
      OpenLoam.as_tenant(tenant, actor: by) do
        reject_self_approval!(by)
        self.reviewed_by_id = by.id
        self.reviewed_at = Time.current
        to_approved!   # NotAuthorizedError if not a manager; InvalidTransitionError if not pending
        execute_and_record!
      end
      self
    end

    def reject!(by:, reason: nil)
      OpenLoam.as_tenant(tenant, actor: by) do
        self.reviewed_by_id = by.id
        self.reviewed_at = Time.current
        self.result = [ "rejected", reason.presence ].compact.join(": ")
        to_rejected!
      end
      self
    end

    private

    # Segregation of duties: the person who staged a change must not be the one
    # who approves it — normally the proposer is an AI agent and the approver a
    # human. Opt out per tenant with the "approvals.allow_self_approve" flag. A
    # proposal with no recorded actor (actor_id nil) bypasses the check.
    # (reject! is deliberately NOT gated: rejecting your own proposal is a
    # withdrawal, not a segregation-of-duties concern.)
    def reject_self_approval!(by)
      return unless by.id == actor_id
      return if OpenLoam::Configs.get("approvals.allow_self_approve", default: false)

      raise OpenLoam::NotAuthorizedError, "self-approval is not permitted; a different person must approve this change"
    end

    # Execution AND its status/result recording share ONE transaction with the
    # target write: if recording the outcome fails after the target committed,
    # the whole thing rolls back rather than leaving the change applied but the
    # status stuck at "approved".
    def execute_and_record!
      ActiveRecord::Base.transaction do
        outcome = execute_change!
        to_executed!
        update!(result: outcome)
      end
    rescue StandardError => error
      # The transaction rolled back, but Active Record leaves the in-memory
      # attributes as they were mid-transaction — reload to the real DB state
      # ("approved") before transitioning to "failed".
      reload
      to_failed!
      update!(error: error.message)
    end

    def execute_change!
      case action_type
      when "create"
        record = target_class.create!(changeset)
        "created #{target_type}##{record.id}"
      when "update"
        target_class.find(target_id).update!(changeset)
        "updated #{target_type}##{target_id}"
      when "destroy"
        target = target_class.find(target_id)
        target.respond_to?(:soft_delete!) ? target.soft_delete! : target.destroy!
        "deleted #{target_type}##{target_id}"
      else
        raise OpenLoam::Error, "unknown action_type #{action_type.inspect}"
      end
    end

    def target_class
      target_type.constantize
    end

    def load_target
      return nil if target_id.nil?

      target_class.find_by(id: target_id)
    end

    def encrypted_target_fields
      return [] unless target_class.respond_to?(:open_loam_encrypted_attributes)

      target_class.open_loam_encrypted_attributes.map(&:to_s)
    end

    # Set while a workflow transition is performing its save, so the validation
    # below can tell a legitimate status move from a direct assignment.
    def open_loam_perform_transition!(transition)
      @open_loam_status_via_transition = true
      super
    ensure
      @open_loam_status_via_transition = false
    end

    def status_changes_only_through_a_transition
      return unless will_save_change_to_status?
      return if @open_loam_status_via_transition

      errors.add(:status, "may only change through an approval transition (approve!/reject!), not a direct write")
    end

    def status_starts_at_the_initial_state
      return if status == self.class.open_loam_workflow.initial

      errors.add(:status, "must start at #{self.class.open_loam_workflow.initial.inspect} — a staged action begins pending")
    end
  end
end
