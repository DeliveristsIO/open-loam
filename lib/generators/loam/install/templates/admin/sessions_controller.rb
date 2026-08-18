module Admin
  # Email + password login for the admin. Two steps, because a Loam user can
  # belong to several tenants: authenticate first, then choose which tenant to
  # work in — and only from tenants where this user actually has a membership.
  #
  # Not a BaseController subclass: everything there assumes an established
  # Loam::Current, which is exactly what this controller is trying to build.
  class SessionsController < ActionController::Base
    layout "admin"

    def new
      @user = authenticated_user
      @tenants = @user ? Loam::Membership.tenants_for(@user) : Loam::Tenant.none
    end

    def create
      user = User.authenticate_by(email: params[:email], password: params[:password])

      if user.nil?
        # One message for both cases on purpose: saying which half was wrong
        # tells an attacker which emails exist.
        @error = "Wrong email or password."
        return render :new, status: :unauthorized
      end

      reset_session # a fresh session id at login: no fixation
      session[:user_id] = user.id

      tenants = Loam::Membership.tenants_for(user)

      if tenants.one?
        enter(tenants.first)
      elsif tenants.none?
        reset_session
        @error = "This account has no tenant memberships yet."
        render :new, status: :forbidden
      else
        redirect_to new_admin_session_path
      end
    end

    # Step two: the tenant picker posts here.
    def select_tenant
      user = authenticated_user
      return redirect_to new_admin_session_path if user.nil?

      tenant = Loam::Membership.tenants_for(user).find_by(id: params[:tenant_id])

      # A tenant the user has no membership in is simply not in that list, so
      # picking one is impossible rather than merely forbidden.
      return redirect_to new_admin_session_path, alert: "You are not a member of that tenant." if tenant.nil?

      enter(tenant)
    end

    def destroy
      reset_session
      Loam::Current.reset
      redirect_to new_admin_session_path
    end

    private

    def authenticated_user
      User.find_by(id: session[:user_id])
    end

    def enter(tenant)
      session[:tenant_id] = tenant.id
      redirect_to admin_root_path
    end
  end
end
