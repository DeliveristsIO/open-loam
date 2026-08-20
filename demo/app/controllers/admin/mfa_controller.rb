module Admin
  # A user's own two-factor setup — self-service, so NOT role-gated (everyone
  # manages their own MFA). Enrollment is two steps: `new` mints a secret and
  # shows it, `create` confirms a live code before activating and revealing the
  # one-time recovery codes. Disabling is sensitive, so it is step-up gated.
  class MfaController < BaseController
    ISSUER = "Loam Demo".freeze

    before_action :require_sudo!, only: :destroy

    def show
      @credential = Loam::MfaCredential.active_for(current_actor)
    end

    # Start (or restart) enrollment: generate a fresh secret and show its URI.
    def new
      @credential = credential_for(current_actor).start_enrollment!
      @provisioning_uri = @credential.provisioning_uri(issuer: ISSUER)
      @secret = @credential.totp_secret
    end

    # Confirm the code, activate, and show the recovery codes exactly once.
    def create
      credential = credential_for(current_actor)
      @recovery_codes = credential.activate!(params[:code])

      if @recovery_codes
        render :activated
      else
        @credential = credential
        @provisioning_uri = credential.provisioning_uri(issuer: ISSUER)
        @secret = credential.totp_secret
        @error = "That code did not match. Check your authenticator and try again."
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      Loam::MfaCredential.where(user_id: current_actor.id).delete_all
      redirect_to admin_mfa_path, notice: "Two-factor authentication disabled."
    end

    private

    # MFA is per-user, so find/build by user_id directly (not tenant-scoped).
    def credential_for(user)
      Loam::MfaCredential.find_or_initialize_by(user_id: user.id)
    end
  end
end
