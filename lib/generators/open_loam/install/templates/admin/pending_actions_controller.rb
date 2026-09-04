module Admin
  # The approval queue: staged mutations (OpenLoam::PendingAction) waiting on a
  # human. Manager-only — approving EXECUTES the change. The workflow's role gate
  # is the deeper enforcement (approve!/reject! raise for a non-manager); this
  # screen is a manager screen on top of it.
  class PendingActionsController < BaseController
    before_action { require_role!(:manager) }
    before_action :set_pending_action, only: %i[approve reject]

    def index
      @pending = OpenLoam::PendingAction.pending.order(created_at: :desc)
    end

    def approve
      @pending_action.approve!(by: current_actor)
      redirect_to admin_pending_actions_path, notice: approval_notice(@pending_action)
    end

    def reject
      @pending_action.reject!(by: current_actor, reason: params[:reason])
      redirect_to admin_pending_actions_path, notice: "Rejected: #{@pending_action.summary}"
    end

    private

    def set_pending_action
      @pending_action = OpenLoam::PendingAction.find(params[:id])
    end

    def approval_notice(pending)
      if pending.executed?
        "Approved and applied: #{pending.summary}"
      else
        "Approved, but execution failed: #{pending.error}"
      end
    end
  end
end
