module Admin
  # The step-up ("sudo") re-challenge. A sensitive action calls require_sudo!,
  # which detours here when the last authentication is stale; a correct password
  # (or TOTP code, if the user has MFA) stamps a fresh sudo timestamp and returns
  # to wherever they were headed.
  class SudoController < BaseController
    def new
    end

    def create
      if reauthenticated?
        session[:sudo_at] = Time.now.to_i
        redirect_to(session.delete(:sudo_return_to).presence || admin_root_path,
                    notice: "Re-authenticated — you can complete the action now.")
      else
        @error = "That did not verify. Try again."
        render :new, status: :unauthorized
      end
    end

    private

    # If the user has MFA, a TOTP or recovery code is the strongest re-proof;
    # otherwise fall back to the password. Either way it is the SAME person in
    # Loam::Current re-confirming, never a way to become someone else.
    def reauthenticated?
      credential = Loam::MfaCredential.active_for(current_actor)
      if credential
        credential.verify_totp(params[:code]) || credential.consume_recovery_code(params[:code])
      else
        User.authenticate_by(email: current_actor.email, password: params[:password].to_s).present?
      end
    end
  end
end
