module Admin
  # A record's change history (OpenLoam::AuditRecord) with one-click Undo (L-704).
  # Undo applies the inverse of a change and records ITSELF as an audit, so
  # undoing an "undo" entry is redo — no separate redo action. Reading needs read
  # on the record; undoing needs update (the same gate as editing it).
  class HistoryController < BaseController
    before_action :set_target

    def index
      authorize!(policy_for(@record), :read?)
      @audits = OpenLoam::AuditRecord
                .where(auditable_type: @record.class.name, auditable_id: @record.id)
                .order(id: :desc).limit(100)
    end

    def undo
      authorize!(policy_for(@record), :update?)
      audit = OpenLoam::AuditRecord.find(params[:id])
      OpenLoam::Undo.undo(audit, policy: policy_for(@record))
      redirect_to admin_history_path(type: @record.class.name, record_id: @record.id), notice: "Change undone."
    rescue OpenLoam::Undo::NotUndoableError => error
      redirect_to admin_history_path(type: @record.class.name, record_id: @record.id), alert: error.message
    end

    private

    # The target record, looked up through its OWN default scope (tenancy holds;
    # a soft-deleted row is still reachable to restore). The type is whitelisted
    # to a OpenLoam::TenantRecord — never a bare constantize of a param.
    def set_target
      klass = params[:type].to_s.safe_constantize
      raise OpenLoam::NotAuthorizedError unless klass.is_a?(Class) && klass < OpenLoam::TenantRecord

      scope = klass.respond_to?(:with_deleted) ? klass.with_deleted : klass.all
      @record = scope.find(params[:record_id])
    end
  end
end
