module Admin
  class BaseController < ActionController::Base
    include Pagination

    layout "admin"

    before_action :set_open_loam_context
    before_action :set_locale

    # Fails an action that never authorized anything. Forgetting `authorize!` is
    # otherwise silent — the screen renders, and nothing says the policy was
    # never consulted.
    #
    # It runs AFTER the action, so it catches the omission in development and in
    # tests; it is not a runtime access-control layer. A `destroy` that forgot to
    # authorize has already destroyed the record by the time this raises.
    after_action :verify_authorized!

    # For screens that are authorized STRUCTURALLY rather than by a policy call —
    # a list scoped to current_actor, a pre-auth screen. The reason is required
    # and shows up in the source, so every exemption is a documented claim rather
    # than a silent opt-out.
    def self.skip_authorization!(reason, **options)
      raise ArgumentError, "skip_authorization! needs a reason" if reason.to_s.strip.empty?

      skip_after_action :verify_authorized!, **options
    end

    rescue_from OpenLoam::NotAuthorizedError do
      render plain: "403 Forbidden — your role does not permit this action.", status: :forbidden
    end

    # A disabled feature is "not here" for this tenant, so it 404s — unlike a
    # policy refusal (403), which is "you may not". Capability vs. person.
    rescue_from OpenLoam::FeatureDisabledError do
      render plain: "404 Not Found — this feature is not enabled for your tenant.", status: :not_found
    end

    # A business rule vetoed a workflow transition — the move is legal, but a
    # rule says "not under these conditions".
    rescue_from OpenLoam::TransitionVetoedError do |error|
      render plain: "422 — #{error.message}", status: :unprocessable_entity
    end

    helper_method :current_tenant, :current_actor, :unread_notification_count, :feature_on?, :pending_approval_count, :current_role, :current_locale, :sort_link, :can?

    private

    # A clickable, stateful column header for the generated index tables (L-401):
    # toggles asc/desc, shows the active-direction arrow, and carries the current
    # search / filter / saved-view state so sorting composes with paging and
    # filtering. The controller whitelists the column against real columns, so a
    # crafted `sort` param can never reach ORDER BY.
    def sort_link(column, label)
      active = params[:sort].to_s == column.to_s
      ascending = active && params[:dir].to_s.casecmp("asc").zero?
      arrow = active ? (ascending ? " ↑" : " ↓") : ""
      carried = respond_to?(:current_index_params, true) ? current_index_params : {}
      helpers.link_to("#{label}#{arrow}", url_for(carried.merge(sort: column, dir: ascending ? "desc" : "asc")))
    end

    # Locale is request state like the tenant: pick it from the switcher (param),
    # remember it in the session, default to OpenLoam.default_locale. Content
    # translations (OpenLoam::Translatable) overlay onto it. Reset with OpenLoam::Current.
    def set_locale
      session[:locale] = params[:locale] if params[:locale].present? && OpenLoam.locales.include?(params[:locale])
      OpenLoam::Current.locale = session[:locale] || OpenLoam.default_locale
      chosen = OpenLoam::Current.locale.to_s
      I18n.locale = chosen if I18n.available_locales.map(&:to_s).include?(chosen)
    end

    def current_locale = OpenLoam::Current.locale

    def current_tenant = OpenLoam::Current.tenant
    def current_actor = OpenLoam::Current.actor

    # Establishes OpenLoam::Current from the session, then proves the actor is
    # allowed to be here.
    #
    # The order is load-bearing. OpenLoam::Membership is itself tenant-scoped, so
    # "is this actor a member?" is a question you can only ask from inside a
    # tenant — the tenant has to be in OpenLoam::Current first, or the check raises
    # OpenLoam::MissingTenantError instead of answering. The `&&` chain below
    # guarantees that: membership is only consulted once both are set.
    #
    # If anything fails, BOTH halves of the context are cleared before the
    # redirect, so a half-established context can never leak into the next
    # request or into a job enqueued from it.
    def set_open_loam_context
      OpenLoam::Current.tenant = OpenLoam::Tenant.find_by(id: session[:tenant_id])
      OpenLoam::Current.actor = User.find_by(id: session[:user_id])

      return if current_tenant && current_actor && member_of_current_tenant?

      OpenLoam::Current.reset
      redirect_to new_admin_session_path
    end

    # Scoped to the current tenant by OpenLoam::TenantRecord, which is the whole
    # point: a membership in some other tenant is not membership here.
    def member_of_current_tenant?
      OpenLoam::Membership.exists?(user_id: current_actor.id)
    end

    # Drives the bell in the admin layout. One COUNT per admin page render,
    # which is fine at this scale; cache it if a screen ever gets hot.
    def unread_notification_count
      return 0 unless current_actor

      OpenLoam::Notification.unread.where(user_id: current_actor.id).count
    end

    # Staged changes awaiting review, for the "Approvals (N)" nav badge.
    def pending_approval_count
      return 0 unless current_tenant

      OpenLoam::PendingAction.pending.count
    end

    def policy_for(record)
      OpenLoam::Policy.for(record)
    end

    def authorize!(policy, action)
      authorized!
      raise OpenLoam::NotAuthorizedError unless policy.public_send(action)
    end

    # Records that this action asked a person-authorization question — marked
    # whether the answer was yes or no, since a refusal is still a check.
    #
    # Call it directly only where the check is an inline `raise` rather than one
    # of the helpers below. Deliberately NOT called by require_feature! (a
    # capability gate) or require_sudo! (step-up), since either marking the
    # action would let a feature-gated screen skip authorization silently.
    def authorized!
      @open_loam_authorized = true
    end

    def verify_authorized!
      return if @open_loam_authorized

      raise OpenLoam::AuthorizationNotPerformedError,
            "#{self.class.name}##{action_name} finished without authorizing. Call authorize!/require_role!/" \
            "require_permission!, or declare `skip_authorization! \"<why>\"` if it is authorized structurally."
    end

    # For admin screens with no per-record policy (e.g. field definitions,
    # which apply to a whole entity_type rather than one record).
    def current_role
      OpenLoam::Membership.find_by(user_id: current_actor&.id)&.role&.to_sym
    end

    def require_role!(*roles)
      authorized!
      raise OpenLoam::NotAuthorizedError unless roles.include?(current_role)
    end

    # Feature-string permission gate (OpenLoam::Permissions) — a finer capability
    # check than require_role!. `can?` is a helper_method so views hide UI a role
    # lacks; require_permission! enforces it (403) server-side.
    def can?(permission)
      OpenLoam.can?(permission)
    end

    def require_permission!(permission)
      authorized!
      raise OpenLoam::NotAuthorizedError unless OpenLoam.can?(permission)
    end

    # Feature guards. These gate a CAPABILITY (is the feature on for this
    # tenant), orthogonal to require_role! / policies, which gate a PERSON.
    # `feature_on?` is a helper_method, so views can hide UI a flag turns off.
    def feature_on?(name)
      OpenLoam::Features.on?(name)
    end

    def require_feature!(name)
      raise OpenLoam::FeatureDisabledError unless OpenLoam::Features.on?(name)
    end

    # Optimistic-locking conflict handling: someone saved this record between the
    # user opening the edit form and submitting it (lock_version mismatch →
    # StaleObjectError). Build a field-level diff of what the user tried to write
    # vs the current saved values, then RELOAD to fresh data so the retry carries
    # the new lock_version — never a 500, never a silent clobber. lock_version is
    # the guarantee; the advisory OpenLoam::RecordLock is only a courtesy warning.
    #
    # Encrypted fields are compared and shown via the reader (decrypted); the raw
    # column is ciphertext that never matches (random IV), so a byte compare would
    # be a false conflict every time.
    def stale_conflict!(record, fields)
      encrypted = record.class.respond_to?(:open_loam_encrypted_attributes) ? record.class.open_loam_encrypted_attributes.map(&:to_s) : []
      attempted = fields.map(&:to_s).index_with { |field| conflict_value(record, field, encrypted) }

      record.reload

      @conflict = fields.map(&:to_s).each_with_object({}) do |field, diff|
        theirs = conflict_value(record, field, encrypted)
        yours = attempted[field]
        diff[field] = { "yours" => yours, "theirs" => theirs } unless yours.to_s == theirs.to_s
      end
      flash.now[:alert] = "This #{record.model_name.human.downcase} changed since you opened it — review the differences and save again."
    end

    def conflict_value(record, field, encrypted)
      encrypted.include?(field) ? record.public_send(field) : record[field]
    end

    # Step-up ("sudo") auth. Orthogonal to role: even a manager re-confirms for a
    # sensitive action if their last authentication was more than SUDO_WINDOW ago.
    # A fresh login or MFA verification stamps session[:sudo_at]; this re-checks
    # it and, when stale, detours through the re-challenge and comes back.
    SUDO_WINDOW = 5.minutes

    def require_sudo!
      return if sudo_fresh?

      # A GET can be replayed after re-auth; a non-GET (a DELETE button) cannot,
      # so we come back to the page it was on and the user repeats the action.
      session[:sudo_return_to] = request.get? ? request.fullpath : request.referer
      redirect_to new_admin_sudo_path
    end

    def sudo_fresh?
      authenticated_at = session[:sudo_at]
      authenticated_at.present? && Time.now.to_i - authenticated_at.to_i < SUDO_WINDOW.to_i
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

      raise OpenLoam::NotAuthorizedError unless policy.update?

      record.files.attach(submitted)
    end

    # Runtime custom fields (see OpenLoam::CustomFields) go through the same
    # field-level enforcement as real columns: only a writable definition's
    # value is ever assigned.
    def assign_custom_fields!(record, params, policy)
      # The form partial nests inputs under the model's param key
      # (equipment[custom_fields][serial_number]), so the values must be read
      # from there — a top-level params[:custom_fields] read silently saves
      # nothing while the redirect still says success. Found by an agent
      # during the first golden-tasks benchmark run.
      submitted = params.dig(record.model_name.param_key, :custom_fields)
      return unless submitted

      submitted.each do |name, value|
        record.set_custom_field(name, value) if policy.custom_field_writable?(name)
      end
    end
  end
end
