module Loam
  # A staged mutation awaiting human approval. When a caller runs under
  # confirm-mode (an MCP tool acting for an AI agent — see Loam.mutation_mode), a
  # write is staged HERE as a preview instead of committing; a manager approves
  # or rejects, and only approval executes it. This is Loam's thesis made
  # concrete: agent-triggered writes are gate-able.
  #
  # The approval gate IS a workflow (Loam::Workflow): pending → (manager) approve
  # / reject → executed / failed. "Who may approve" lives in one declarative,
  # role-gated place. The proposed changes are encrypted at rest (Loam::Encryptable),
  # because a staged change to an encrypted target field would otherwise sit here
  # — and in this row's own audit — as plaintext, reopening the leak L-901 closed.
  class PendingAction < Loam::TenantRecord
    self.table_name = "loam_pending_actions"

    include Loam::Auditable
    include Loam::Encryptable
    include Loam::Workflow

    belongs_to :actor, class_name: "User", optional: true
    belongs_to :reviewer, class_name: "User", foreign_key: :reviewed_by_id, optional: true

    # Encrypted JSON. Encryptable also makes Auditable redact `changeset` to
    # "[encrypted]" automatically, so the proposal never lands in the audit trail.
    encrypts :changeset

    validates :action_type, :summary, :idempotency_key, presence: true
    validates :idempotency_key, uniqueness: { scope: :tenant_id }

    # The review queue: still awaiting a decision.
    scope :pending, -> { where(status: "pending") }

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
      Loam.as_tenant(tenant, actor: by) do
        self.reviewed_by_id = by.id
        self.reviewed_at = Time.current
        to_approved!   # NotAuthorizedError if not a manager; InvalidTransitionError if not pending
        execute_and_record!
      end
      self
    end

    def reject!(by:, reason: nil)
      Loam.as_tenant(tenant, actor: by) do
        self.reviewed_by_id = by.id
        self.reviewed_at = Time.current
        self.result = [ "rejected", reason.presence ].compact.join(": ")
        to_rejected!
      end
      self
    end

    private

    def execute_and_record!
      outcome = ActiveRecord::Base.transaction { execute_change! }
      to_executed!
      update!(result: outcome)
    rescue StandardError => error
      # The transaction rolled the target write back; record the failure OUTSIDE
      # it, so the "failed" status and the error persist.
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
        raise Loam::Error, "unknown action_type #{action_type.inspect}"
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
      return [] unless target_class.respond_to?(:loam_encrypted_attributes)

      target_class.loam_encrypted_attributes.map(&:to_s)
    end
  end
end
