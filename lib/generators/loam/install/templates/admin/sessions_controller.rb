module Admin
  # Email + password login for the admin, then (if the user has MFA) a TOTP
  # challenge, then the tenant pick. A Loam user can belong to several tenants,
  # so: authenticate → second factor → choose a tenant where they hold a
  # membership. The second factor runs BEFORE any tenant is chosen, which is why
  # the MFA secret is keyed to the user, not a tenant (Loam::MfaCredential).
  #
  # Not a BaseController subclass: everything there assumes an established
  # Loam::Current, which is exactly what this controller is trying to build.
  class SessionsController < ActionController::Base
    layout "admin"

    def new
      return redirect_to mfa_challenge_admin_session_path if session[:mfa_pending]

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

      # Password is only the first factor when MFA is active — hold the login in
      # a "pending" state (no tenant, no access) until the code checks out.
      if Loam::MfaCredential.active_for(user)
        session[:mfa_pending] = true
        redirect_to mfa_challenge_admin_session_path
      else
        complete_authentication(user)
      end
    end

    # The TOTP challenge screen (only reachable mid-login, password already given).
    def mfa_challenge
      @user = mfa_challenge_user or return redirect_to new_admin_session_path
    end

    def mfa_verify
      user = mfa_challenge_user or return redirect_to new_admin_session_path
      credential = Loam::MfaCredential.active_for(user)

      if credential.verify_totp(params[:code]) || credential.consume_recovery_code(params[:code])
        session.delete(:mfa_pending)
        complete_authentication(user)
      else
        # One generic error — never reveal whether a code was close or a
        # recovery code was already spent.
        @user = user
        @error = "That code is not valid."
        render :mfa_challenge, status: :unauthorized
      end
    end

    # Step two (or three): the tenant picker posts here.
    def select_tenant
      return redirect_to mfa_challenge_admin_session_path if session[:mfa_pending]

      user = authenticated_user
      return redirect_to new_admin_session_path if user.nil?

      tenant = Loam::Membership.tenants_for(user).find_by(id: params[:tenant_id])

      # A tenant the user has no membership in is simply not in that list, so
      # picking one is impossible rather than merely forbidden.
      return redirect_to new_admin_session_path, alert: "You are not a member of that tenant." if tenant.nil?

      enter(user, tenant)
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

    # The signed-in user mid-MFA, or nil. Both the pending flag AND the user id
    # must be present, so the challenge is never an oracle reachable without a
    # password.
    def mfa_challenge_user
      return nil unless session[:mfa_pending] && session[:user_id]

      authenticated_user
    end

    # Both factors are satisfied here, so this counts as a fresh re-auth: stamp
    # the sudo clock, so a step-up-gated action right after login does not
    # immediately re-challenge.
    def complete_authentication(user)
      session[:sudo_at] = Time.now.to_i

      tenants = Loam::Membership.tenants_for(user)

      if tenants.one?
        enter(user, tenants.first)
      elsif tenants.none?
        reset_session
        @error = "This account has no tenant memberships yet."
        render :new, status: :forbidden
      else
        redirect_to new_admin_session_path
      end
    end

    def enter(user, tenant)
      session[:tenant_id] = tenant.id

      if mfa_enrollment_required?(user, tenant)
        redirect_to new_admin_mfa_path, alert: "Your role requires two-factor authentication — set it up to continue."
      else
        redirect_to admin_root_path
      end
    end

    # A tenant may require MFA for certain roles (security.mfa_required_roles,
    # resolved in that tenant). If the user's role is on the list and they have
    # no active credential, they are sent to enrollment before they can work.
    def mfa_enrollment_required?(user, tenant)
      return false if Loam::MfaCredential.active_for(user)

      Loam.as_tenant(tenant) do
        role = Loam::Membership.find_by(user_id: user.id)&.role
        role.present? && Array(Loam::Configs.get("security.mfa_required_roles", default: [])).include?(role)
      end
    end
  end
end
