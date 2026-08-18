module Api
  # Base class for every JSON endpoint. Authentication is a bearer token:
  #
  #   curl -H "Authorization: Bearer <token>" http://localhost:3000/api/equipment
  #
  # A token identifies one user in one tenant, and `Loam::ApiToken.authenticate`
  # establishes both in Loam::Current before any action runs. From that point
  # on this is ordinary tenant-scoped Loam code: every query is filtered, every
  # write is audited, every policy applies — the API is not a side door.
  #
  # Finding a token is the one lookup that cannot start from a tenant (the
  # token is what reveals the tenant), which is why it lives in the gem rather
  # than here: host app code must never reach across tenants.
  class BaseController < ActionController::API
    before_action :authenticate_api_token!

    rescue_from Loam::NotAuthorizedError do
      render json: { error: "forbidden" }, status: :forbidden
    end

    rescue_from ActiveRecord::RecordNotFound do
      render json: { error: "not_found" }, status: :not_found
    end

    rescue_from Loam::UnknownCustomFieldError do |error|
      render json: { error: error.message }, status: :unprocessable_entity
    end

    private

    def authenticate_api_token!
      @api_token = Loam::ApiToken.authenticate(bearer_token)

      render json: { error: "unauthorized" }, status: :unauthorized unless @api_token
    end

    def bearer_token
      request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]
    end

    def current_tenant = Loam::Current.tenant
    def current_actor = Loam::Current.actor

    def policy_for(record)
      Loam::Policy.for(record)
    end

    def authorize!(policy, action)
      raise Loam::NotAuthorizedError unless policy.public_send(action)
    end

    # The JSON shape of an entity: its columns, custom fields included (they
    # live in the `custom_fields` column that every generated entity carries).
    def entity_json(record)
      record.attributes
    end

    # Same field-level enforcement as the admin screens: only a definition the
    # actor's role may write is assigned. Custom fields ride at the top level
    # of the request body, beside the entity key.
    def assign_custom_fields!(record, params, policy)
      submitted = params[:custom_fields]
      return unless submitted

      submitted.each do |name, value|
        record.set_custom_field(name, value) if policy.custom_field_writable?(name)
      end
    end
  end
end
