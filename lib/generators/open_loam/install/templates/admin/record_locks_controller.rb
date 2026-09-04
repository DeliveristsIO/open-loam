module Admin
  # Manager take-over of an advisory edit lock (Loam::RecordLocks). Only a
  # manager may force-release someone else's lock; the record it points at is
  # resolved through a whitelist (a Loam::TenantRecord subclass), never a raw
  # constantize of user input.
  class RecordLocksController < BaseController
    before_action { require_role!(:manager) }

    def destroy
      klass = params[:lockable_type].to_s.safe_constantize
      raise Loam::NotAuthorizedError unless klass && klass < Loam::TenantRecord

      Loam::RecordLocks.force_release(klass.find(params[:lockable_id]))
      redirect_back fallback_location: admin_root_path, notice: "Lock released — you can edit now."
    end
  end
end
