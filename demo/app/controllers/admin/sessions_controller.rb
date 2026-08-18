module Admin
  # Prototype-only context switcher: pick a user and a tenant instead of real
  # authentication. Replace with Devise/your auth in a real app — Loam only
  # needs session[:tenant_id] and session[:user_id] resolved in BaseController.
  class SessionsController < ActionController::Base
    layout "admin"

    def new
      @tenants = Loam::Tenant.order(:name)
      @users = User.order(:name)
    end

    def create
      session[:tenant_id] = params[:tenant_id]
      session[:user_id] = params[:user_id]
      redirect_to admin_root_path
    end

    def destroy
      reset_session
      redirect_to new_admin_session_path
    end
  end
end
