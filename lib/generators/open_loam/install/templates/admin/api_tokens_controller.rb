module Admin
  # Your own API tokens, and only ever your own: every query is scoped to
  # current_actor, so there is no path to another user's credentials. A token
  # acts as its user in this tenant, which is precisely why nobody else may
  # list, create or revoke one for you.
  class ApiTokensController < BaseController
    skip_authorization! "Every query is scoped to current_actor — a token is only ever your own."

    def index
      @records = api_tokens.order(created_at: :desc)
    end

    def create
      token = api_tokens.create!(label: params[:label].presence || "API token")

      # Shown once, on the next screen — the habit that matters when tokens
      # are eventually stored hashed rather than in the clear.
      redirect_to admin_api_tokens_path, flash: { token: token.token }
    end

    def destroy
      api_tokens.find(params[:id]).destroy!
      redirect_to admin_api_tokens_path
    end

    private

    def api_tokens
      OpenLoam::ApiToken.where(user_id: current_actor.id)
    end
  end
end
