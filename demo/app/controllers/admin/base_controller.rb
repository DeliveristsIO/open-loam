module Admin
  class BaseController < ActionController::Base
    layout "admin"

    before_action :set_loam_context

    rescue_from Loam::NotAuthorizedError do
      render plain: "403 Forbidden — your role does not permit this action.", status: :forbidden
    end

    helper_method :current_tenant, :current_actor

    private

    def current_tenant = Loam::Current.tenant
    def current_actor = Loam::Current.actor

    def set_loam_context
      Loam::Current.tenant = Loam::Tenant.find_by(id: session[:tenant_id])
      Loam::Current.actor = User.find_by(id: session[:user_id])

      redirect_to new_admin_session_path unless current_tenant && current_actor
    end

    def policy_for(record)
      Loam::Policy.for(record)
    end

    def authorize!(policy, action)
      raise Loam::NotAuthorizedError unless policy.public_send(action)
    end
  end
end
