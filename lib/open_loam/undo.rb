module Loam
  # Undo/redo built ON the audit trail (L-704). Every change already records a
  # Loam::AuditRecord with its changeset; undoing one applies the inverse and
  # writes a NEW audit record — so the inverse is itself undoable, and "redo" is
  # just undoing that undo entry. No separate command log to keep in sync.
  #
  # THE STACK: a field revert is refused unless the audit is the record's LATEST
  # update/undo — undoing an old change out from under newer ones would silently
  # clobber them. Undo therefore walks the history back one entry at a time.
  #
  # BOUNDARIES (each a deliberate skip, not a gap):
  #   * encrypted fields — the audit stores "[encrypted]", never the old value,
  #     so there is nothing to revert to;
  #   * the workflow column — a direct write is blocked by the transition gate
  #     (Loam::Workflow), so state is undone by performing the reverse TRANSITION,
  #     not here;
  #   * fields the actor's role may not write (when a policy is supplied).
  module Undo
    class NotUndoableError < Loam::Error; end

    IGNORE = %w[id lock_version created_at updated_at].freeze

    module_function

    # Coarse, action-level check the admin view consults to decide whether to
    # offer an Undo button. The fine checks (something revertable, still latest)
    # happen in `undo` and surface as NotUndoableError.
    def undoable?(audit)
      case audit.action
      when "update", "undo"                    then true
      when "create", "soft_delete", "restore"  then soft_deletable?(audit)
      else false
      end
    end

    # Apply the inverse of one audit record. Returns the affected record.
    # `policy:` (optional) restricts a field revert to policy-writable fields.
    def undo(audit, policy: nil)
      ensure_current_tenant!(audit)
      record = load_record(audit)

      case audit.action
      when "update", "undo" then revert_fields(record, audit, policy)
      when "create"         then undo_create(record)
      when "soft_delete"    then guard_soft_delete(record).restore!
      when "restore"        then guard_soft_delete(record).soft_delete!
      else raise NotUndoableError, "#{audit.action.inspect} cannot be undone"
      end
      record
    end

    # --- internals ---

    def revert_fields(record, audit, policy)
      ensure_latest!(audit)
      workflow_column = record.class.respond_to?(:loam_workflow) ? record.class.loam_workflow&.column.to_s : nil

      updates = {}
      (audit.changeset || {}).each do |field, values|
        next unless values.is_a?(Array)                 # skip "[encrypted]" (a String)
        next if IGNORE.include?(field)
        next if field == workflow_column                # undo state via the reverse transition, not a direct write
        next unless record.class.column_names.include?(field)
        next if policy && !policy.writable?(field)

        updates[field] = values.first                   # the "before" value
      end

      raise NotUndoableError, "nothing revertable in this change" if updates.empty?

      # Relabel this save's audit as "undo" so the history reads legibly (and the
      # entry is itself undoable = redo). loam_audit_as is the same hook
      # SoftDeletable uses for soft_delete/restore.
      if record.respond_to?(:loam_audit_as, true)
        record.send(:loam_audit_as, "undo") { record.update!(updates) }
      else
        record.update!(updates)
      end
    end

    def undo_create(record)
      guard_soft_delete(record).soft_delete!
    end

    def guard_soft_delete(record)
      unless record.respond_to?(:soft_delete!) && record.respond_to?(:restore!)
        raise NotUndoableError, "#{record.class.name} is not soft-deletable, so this change can't be undone"
      end
      record
    end

    # The audit must be the record's most recent update/undo — else undoing it
    # would overwrite newer edits. Tenant-scoped via AuditRecord's default scope.
    def ensure_latest!(audit)
      latest = Loam::AuditRecord
               .where(auditable_type: audit.auditable_type, auditable_id: audit.auditable_id, action: %w[update undo])
               .order(:id).last
      return if latest.nil? || latest.id == audit.id

      raise NotUndoableError, "a newer change exists — undo that first"
    end

    # Look the record up through its OWN default scope (tenant holds), lifting
    # only the soft-delete filter so a soft-deleted row is still reachable to
    # restore. Never AuditRecord#auditable, which is unscoped.
    def load_record(audit)
      klass = audit.auditable_type.safe_constantize
      raise NotUndoableError, "unknown type #{audit.auditable_type.inspect}" unless klass.is_a?(Class) && klass < Loam::TenantRecord

      scope = klass.respond_to?(:with_deleted) ? klass.with_deleted : klass.all
      record = scope.find_by(id: audit.auditable_id)
      raise NotUndoableError, "the record no longer exists" unless record

      record
    end

    def soft_deletable?(audit)
      klass = audit.auditable_type.safe_constantize
      klass.is_a?(Class) && klass.instance_methods.include?(:soft_delete!)
    end

    def ensure_current_tenant!(audit)
      raise NotUndoableError, "not in this tenant" unless audit.tenant_id == Loam.tenant!.id
    end
  end
end
