module Admin
  # Your own API tokens — creating and listing is scoped to current_actor, so
  # there is no path to another user's credentials. Revoking is the exception: a
  # manager owns offboarding, and a token that outlives someone's access is the
  # thing offboarding is supposed to end.
  class ApiTokensController < BaseController
    skip_authorization! "Scoped to current_actor; the manager-wide revoke path calls require_role! itself."

    # Revoking an API token cuts off a machine's access — sensitive enough to
    # re-confirm, even for a manager (step-up is orthogonal to role).
    before_action :require_sudo!, only: :destroy

    def index
      @records = api_tokens.order(created_at: :desc)
      # Only the label, owner and usage — never a token value, which no longer
      # exists in a readable form anyway.
      @tenant_records = manager? ? OpenLoam::ApiToken.where.not(user_id: current_actor.id).order(created_at: :desc) : []
    end

    def create
      token = api_tokens.create!(label: params[:label].presence || "API token")

      # The only time the plaintext exists: only its digest is stored, so this
      # screen is genuinely the last chance to copy it.
      redirect_to admin_api_tokens_path, flash: { token: token.token }
    end

    def destroy
      # Tenant-scoped by the default scope, so another tenant's token is not
      # merely forbidden here — it is not findable.
      record = OpenLoam::ApiToken.find(params[:id])
      require_role!(:manager) unless record.user_id == current_actor.id

      record.destroy!
      redirect_to admin_api_tokens_path
    end

    private

    def api_tokens
      OpenLoam::ApiToken.where(user_id: current_actor.id)
    end

    def manager?
      current_role == :manager
    end
  end
end
