module Admin
  class BaseController < ActionController::Base
    layout "admin"

    before_action :set_loam_context

    rescue_from Loam::NotAuthorizedError do
      render plain: "403 Forbidden — your role does not permit this action.", status: :forbidden
    end

    helper_method :current_tenant, :current_actor

    private

    def current_tenant = Loam::Current.tenant
    def current_actor = Loam::Current.actor

    def set_loam_context
      Loam::Current.tenant = Loam::Tenant.find_by(id: session[:tenant_id])
      Loam::Current.actor = User.find_by(id: session[:user_id])

      redirect_to new_admin_session_path unless current_tenant && current_actor
    end

    def policy_for(record)
      Loam::Policy.for(record)
    end

    def authorize!(policy, action)
      raise Loam::NotAuthorizedError unless policy.public_send(action)
    end

    # For admin screens with no per-record policy (e.g. field definitions,
    # which apply to a whole entity_type rather than one record).
    def current_role
      Loam::Membership.find_by(user_id: current_actor&.id)&.role&.to_sym
    end

    def require_role!(*roles)
      raise Loam::NotAuthorizedError unless roles.include?(current_role)
    end

    # Runtime custom fields (see Loam::CustomFields) go through the same
    # field-level enforcement as real columns: only a writable definition's
    # value is ever assigned.
    def assign_custom_fields!(record, params, policy)
      submitted = params[:custom_fields]
      return unless submitted

      submitted.each do |name, value|
        record.set_custom_field(name, value) if policy.custom_field_writable?(name)
      end
    end
  end
end
