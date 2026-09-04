module Admin
  # Manager take-over of an advisory edit lock (OpenLoam::RecordLocks). Only a
  # manager may force-release someone else's lock; the record it points at is
  # resolved through a whitelist (a OpenLoam::TenantRecord subclass), never a raw
  # constantize of user input.
  class RecordLocksController < BaseController
    before_action { require_role!(:manager) }

    def destroy
      klass = params[:lockable_type].to_s.safe_constantize
      raise OpenLoam::NotAuthorizedError unless klass && klass < OpenLoam::TenantRecord

      OpenLoam::RecordLocks.force_release(klass.find(params[:lockable_id]))
      redirect_back fallback_location: admin_root_path, notice: "Lock released — you can edit now."
    end
  end
end
