module Admin
  # The bell. Every query here is scoped to the current actor, so there is no
  # "read someone else's notifications" path to authorize and no per-record
  # policy to write: tenancy is structural (OpenLoam::Notification is a
  # OpenLoam::TenantRecord) and BaseController has already established that this
  # actor is signed in to this tenant. Recipient scoping is the whole rule.
  class NotificationsController < BaseController
    def index
      @records = notifications.order(created_at: :desc).limit(100)
    end

    def mark_read
      notifications.find(params[:id]).mark_read!
      redirect_to admin_notifications_path
    end

    private

    def notifications
      OpenLoam::Notification.where(user_id: current_actor.id)
    end
  end
end
