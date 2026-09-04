module Admin
  # A user's own two-factor setup — self-service, so NOT role-gated (everyone
  # manages their own MFA). Enrollment is two steps: `new` (GET) shows a
  # CANDIDATE secret held in the session, `create` (POST) confirms a live code
  # and only then adopts it. Crucially, GET never mutates the credential, and the
  # old secret stays valid until the new one is proven — so neither a cross-site
  # GET nor an abandoned re-enrollment can downgrade an active credential.
  class MfaController < BaseController
    # Shown in authenticator apps as the account issuer; defaults to the app name.
    ISSUER = Rails.application.class.module_parent_name.freeze

    # Replacing an ACTIVE credential (or disabling it) is sensitive, so gate those
    # writes behind step-up. Initial enrollment (no active MFA yet) needs no sudo
    # — there is nothing to protect and no second factor to prove.
    before_action :require_sudo!, only: %i[create destroy], if: :active_mfa?

    def show
      @credential = OpenLoam::MfaCredential.active_for(current_actor)
    end

    # READ-ONLY: mint a candidate secret into the (encrypted cookie) session and
    # display it. No credential is touched, so this is safe to reach via GET.
    def new
      set_enrollment_secret
    end

    # Confirm the candidate against a live code, then adopt it and reveal the
    # recovery codes once. The active secret is replaced only on success.
    def create
      secret = session[:mfa_enrollment_secret]
      credential = OpenLoam::MfaCredential.find_or_initialize_by(user_id: current_actor.id)
      @recovery_codes = secret && credential.activate_with!(secret, params[:code])

      if @recovery_codes
        session.delete(:mfa_enrollment_secret)
        render :activated
      else
        set_enrollment_secret
        @error = "That code did not match. Check your authenticator and try again."
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      OpenLoam::MfaCredential.where(user_id: current_actor.id).delete_all
      session.delete(:mfa_enrollment_secret)
      redirect_to admin_mfa_path, notice: "Two-factor authentication disabled."
    end

    private

    def set_enrollment_secret
      @secret = (session[:mfa_enrollment_secret] ||= OpenLoam::Totp.generate_secret)
      @provisioning_uri = OpenLoam::Totp.provisioning_uri(@secret, account: current_actor.email, issuer: ISSUER)
    end

    def active_mfa?
      OpenLoam::MfaCredential.active_for(current_actor).present?
    end
  end
end
