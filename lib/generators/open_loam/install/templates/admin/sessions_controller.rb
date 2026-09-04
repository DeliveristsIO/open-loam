module Admin
  # Email + password login for the admin, then (if the user has MFA) a TOTP
  # challenge, then the tenant pick. A OpenLoam user can belong to several tenants,
  # so: authenticate → second factor → choose a tenant where they hold a
  # membership. The second factor runs BEFORE any tenant is chosen, which is why
  # the MFA secret is keyed to the user, not a tenant (OpenLoam::MfaCredential).
  #
  # Not a BaseController subclass: everything there assumes an established
  # OpenLoam::Current, which is exactly what this controller is trying to build.
  class SessionsController < ActionController::Base
    layout "admin"

    def new
      return redirect_to mfa_challenge_admin_session_path if session[:mfa_pending]

      @user = authenticated_user
      @tenants = @user ? OpenLoam::Membership.tenants_for(@user) : OpenLoam::Tenant.none
    end

    def create
      email = params[:email]

      # Rate-limit BEFORE touching the password (OpenLoam::AuthThrottle). Throttle by
      # the submitted identifier whether or not the account exists, and give the
      # SAME generic locked response either way — so a lockout can't become an
      # account-existence oracle.
      if OpenLoam::AuthThrottle.locked?(email)
        @error = throttle_message(email)
        return render :new, status: :too_many_requests
      end

      user = User.authenticate_by(email: email, password: params[:password])

      if user.nil?
        OpenLoam::AuthThrottle.record_failure(email, kind: "password", ip: request.remote_ip)
        # One message for both cases on purpose: saying which half was wrong
        # tells an attacker which emails exist.
        @error = "Wrong email or password."
        return render :new, status: :unauthorized
      end

      OpenLoam::AuthThrottle.clear(email) # a successful login resets the counter
      reset_session # a fresh session id at login: no fixation
      session[:user_id] = user.id

      # Password is only the first factor when MFA is active — hold the login in
      # a "pending" state (no tenant, no access) until the code checks out.
      if OpenLoam::MfaCredential.active_for(user)
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

    # TODO (follow-up): rate-limit / lock out repeated failed codes here (needs
    # throttling infra) — a 6-digit TOTP is brute-forceable without it.
    def mfa_verify
      user = mfa_challenge_user or return redirect_to new_admin_session_path

      # A 6-digit TOTP (with drift, several codes valid) is the prime brute-force
      # target — lock it out on the user's identifier.
      if OpenLoam::AuthThrottle.locked?(user.email)
        @user = user
        @error = throttle_message(user.email)
        return render :mfa_challenge, status: :too_many_requests
      end

      credential = OpenLoam::MfaCredential.active_for(user)

      if credential.verify_totp(params[:code]) || credential.consume_recovery_code(params[:code])
        OpenLoam::AuthThrottle.clear(user.email)
        session.delete(:mfa_pending)
        complete_authentication(user)
      else
        OpenLoam::AuthThrottle.record_failure(user.email, kind: "totp", ip: request.remote_ip)
        # One generic error — never reveal whether a code was close or a
        # recovery code was already spent.
        @user = user
        @error = "That code is not valid."
        render :mfa_challenge, status: :unauthorized
      end
    end

    # SSO entry: the user types an email, home-realm discovery finds the tenant's
    # IdP by domain, and we redirect to it. No provider for that domain? Fall
    # back to password login. The `state` is our CSRF token for the round-trip.
    def sso_start
      email = params[:email].to_s
      provider = OpenLoam::Sso.provider_for(email: email)

      if provider.nil?
        return redirect_to new_admin_session_path(email: email),
                           alert: "No SSO provider is configured for that email domain — sign in with your password."
      end

      state = SecureRandom.urlsafe_base64(24)
      reset_session
      session[:sso_state] = state
      session[:sso_provider_id] = provider.id
      session[:sso_tenant_id] = provider.tenant_id

      url = OpenLoam.as_tenant(provider.tenant) do
        OpenLoam::Sso.build(provider, redirect_uri: sso_callback_admin_session_url)
                 .authorization_url(state: state, login_hint: email)
      end
      redirect_to url, allow_other_host: true
    end

    # The IdP redirects back here with a code + state. GET, so Rails' form CSRF
    # does not apply — the `state` check IS the CSRF defense. Verify it first,
    # then exchange the code and provision inside the provider's tenant.
    def sso_callback
      state = session.delete(:sso_state)
      provider_id = session.delete(:sso_provider_id)
      tenant_id = session.delete(:sso_tenant_id)

      if state.blank? || !ActiveSupport::SecurityUtils.secure_compare(state, params[:state].to_s)
        return redirect_to new_admin_session_path, alert: "SSO sign-in could not be verified. Please try again."
      end

      tenant = OpenLoam::Tenant.find_by(id: tenant_id)
      provider = tenant && OpenLoam.as_tenant(tenant) { OpenLoam::SsoProvider.find_by(id: provider_id) }
      if provider.nil? || !provider.active?
        return redirect_to new_admin_session_path, alert: "That SSO provider is no longer available."
      end

      user = OpenLoam.as_tenant(tenant) do
        claims = OpenLoam::Sso.build(provider, redirect_uri: sso_callback_admin_session_url).exchange(code: params[:code])
        OpenLoam::Sso.provision(provider, claims)
      end

      reset_session
      session[:user_id] = user.id
      session[:sso_tenant_id] = tenant.id  # land in the IdP's tenant after any MFA

      # SSO establishes primary auth; if the user also runs app-side MFA, still
      # require the second factor (the safe choice — SSO does not waive it).
      if OpenLoam::MfaCredential.active_for(user)
        session[:mfa_pending] = true
        redirect_to mfa_challenge_admin_session_path
      else
        complete_authentication(user)
      end
    rescue OpenLoam::Sso::Error
      # An unverified email, a domain the provider does not own, or any other
      # provisioning refusal: no session, nothing linked, one generic message.
      reset_session
      redirect_to new_admin_session_path,
                  alert: "We couldn't sign you in with SSO. Please contact your administrator."
    end

    # Step two (or three): the tenant picker posts here.
    def select_tenant
      return redirect_to mfa_challenge_admin_session_path if session[:mfa_pending]

      user = authenticated_user
      return redirect_to new_admin_session_path if user.nil?

      tenant = OpenLoam::Membership.tenants_for(user).find_by(id: params[:tenant_id])

      # A tenant the user has no membership in is simply not in that list, so
      # picking one is impossible rather than merely forbidden.
      return redirect_to new_admin_session_path, alert: "You are not a member of that tenant." if tenant.nil?

      enter(user, tenant)
    end

    def destroy
      reset_session
      OpenLoam::Current.reset
      redirect_to new_admin_session_path
    end

    private

    def authenticated_user
      User.find_by(id: session[:user_id])
    end

    def throttle_message(identifier)
      minutes = (OpenLoam::AuthThrottle.remaining_lockout(identifier) / 60.0).ceil
      "Too many attempts. Try again in about #{[ minutes, 1 ].max} minute(s)."
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

      # SSO knows exactly which tenant to enter (the IdP's), so honor it even for
      # a multi-tenant user rather than showing the picker.
      if (sso_tenant_id = session.delete(:sso_tenant_id))
        tenant = OpenLoam::Membership.tenants_for(user).find_by(id: sso_tenant_id)
        return enter(user, tenant) if tenant
      end

      tenants = OpenLoam::Membership.tenants_for(user)

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
      return false if OpenLoam::MfaCredential.active_for(user)

      OpenLoam.as_tenant(tenant) do
        role = OpenLoam::Membership.find_by(user_id: user.id)&.role
        role.present? && Array(OpenLoam::Configs.get("security.mfa_required_roles", default: [])).include?(role)
      end
    end
  end
end
