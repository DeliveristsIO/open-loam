module Api
  # Base class for every JSON endpoint. Authentication is a bearer token:
  #
  #   curl -H "Authorization: Bearer <token>" http://localhost:3000/api/equipment
  #
  # A token identifies one user in one tenant, and `OpenLoam::ApiToken.authenticate`
  # establishes both in OpenLoam::Current before any action runs. From that point
  # on this is ordinary tenant-scoped OpenLoam code: every query is filtered, every
  # write is audited, every policy applies — the API is not a side door.
  #
  # Finding a token is the one lookup that cannot start from a tenant (the
  # token is what reveals the tenant), which is why it lives in the gem rather
  # than here: host app code must never reach across tenants.
  class BaseController < ActionController::API
    before_action :authenticate_api_token!

    rescue_from OpenLoam::NotAuthorizedError do
      render json: { error: "forbidden" }, status: :forbidden
    end

    rescue_from ActiveRecord::RecordNotFound do
      render json: { error: "not_found" }, status: :not_found
    end

    rescue_from OpenLoam::UnknownCustomFieldError do |error|
      render json: { error: error.message }, status: :unprocessable_entity
    end

    private

    def authenticate_api_token!
      @api_token = OpenLoam::ApiToken.authenticate(bearer_token)

      render json: { error: "unauthorized" }, status: :unauthorized unless @api_token
    end

    def bearer_token
      request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]
    end

    def current_tenant = OpenLoam::Current.tenant
    def current_actor = OpenLoam::Current.actor

    def policy_for(record)
      OpenLoam::Policy.for(record)
    end

    def authorize!(policy, action)
      raise OpenLoam::NotAuthorizedError unless policy.public_send(action)
    end

    # The JSON shape of an entity: its columns, custom fields included (they
    # live in the `custom_fields` column that every generated entity carries).
    #
    # Encrypted fields (OpenLoam::Encryptable) are returned DECRYPTED — the caller is
    # authenticated, tenant-scoped and policy-gated, exactly like the admin show
    # screen — and their blind-index `<field>_hash` column is dropped, so the
    # equality-leaking hash never goes over the wire. `record.attributes` alone
    # would emit the raw ciphertext plus the hash.
    def entity_json(record, enrichments: nil)
      json = record.attributes

      if record.class.respond_to?(:open_loam_encrypted_attributes)
        record.class.open_loam_encrypted_attributes.each do |name|
          json[name] = record.public_send(name)
          json.delete("#{name}_hash")
        end
      end

      # Computed cross-module blocks (OpenLoam::Enrichers), under a separate key so
      # they're never confused with the record's own columns. An index passes the
      # batched result (avoiding N+1); a single show computes it here.
      enrichments = OpenLoam::Enrichers.enrich(record) if enrichments.nil?
      json["enrichments"] = enrichments if enrichments.present?
      json
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
