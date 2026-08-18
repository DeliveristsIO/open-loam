module Admin
  class BaseController < ActionController::Base
    layout "admin"

    before_action :set_loam_context

    rescue_from Loam::NotAuthorizedError do
      render plain: "403 Forbidden — your role does not permit this action.", status: :forbidden
    end

    helper_method :current_tenant, :current_actor, :unread_notification_count

    private

    def current_tenant = Loam::Current.tenant
    def current_actor = Loam::Current.actor

    # Establishes Loam::Current from the session, then proves the actor is
    # allowed to be here.
    #
    # The order is load-bearing. Loam::Membership is itself tenant-scoped, so
    # "is this actor a member?" is a question you can only ask from inside a
    # tenant — the tenant has to be in Loam::Current first, or the check raises
    # Loam::MissingTenantError instead of answering. The `&&` chain below
    # guarantees that: membership is only consulted once both are set.
    #
    # If anything fails, BOTH halves of the context are cleared before the
    # redirect, so a half-established context can never leak into the next
    # request or into a job enqueued from it.
    def set_loam_context
      Loam::Current.tenant = Loam::Tenant.find_by(id: session[:tenant_id])
      Loam::Current.actor = User.find_by(id: session[:user_id])

      return if current_tenant && current_actor && member_of_current_tenant?

      Loam::Current.reset
      redirect_to new_admin_session_path
    end

    # Scoped to the current tenant by Loam::TenantRecord, which is the whole
    # point: a membership in some other tenant is not membership here.
    def member_of_current_tenant?
      Loam::Membership.exists?(user_id: current_actor.id)
    end

    # Drives the bell in the admin layout. One COUNT per admin page render,
    # which is fine at this scale; cache it if a screen ever gets hot.
    def unread_notification_count
      return 0 unless current_actor

      Loam::Notification.unread.where(user_id: current_actor.id).count
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

    # Attaching a file changes the record, so it is an update: a role that may
    # not update this record may not put files on it either.
    #
    # A `multiple: true` file field posts an empty string alongside any real
    # files, so blanks are dropped BEFORE the authorization check — submitting
    # a form with no file chosen is not an attempt to upload.
    def attach_files!(record, policy)
      submitted = Array(params.dig(record.model_name.param_key, :files)).reject(&:blank?)
      return if submitted.empty?

      raise Loam::NotAuthorizedError unless policy.update?

      record.files.attach(submitted)
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
