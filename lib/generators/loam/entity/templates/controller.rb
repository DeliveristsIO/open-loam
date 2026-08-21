module Admin
  class <%= plural_name.camelize %>Controller < BaseController
    FIELDS = %i[<%= field_names.join(" ") %>].freeze

    before_action :set_record, only: %i[show edit update destroy]

    def index
      @perspective = Loam::Perspectives.resolve("<%= class_name %>", user: current_actor, id: params[:perspective_id])
      @perspectives = Loam::Perspectives.visible_to("<%= class_name %>", user: current_actor)
      @records, @page, @has_next = paginate(index_scope)
    end

    # CSV of the CURRENT filtered/perspective view — manager-only, policy- and
    # encryption-aware (Loam::Export).
    def export
      require_role!(:manager)
      send_data Loam::Export.csv(index_scope, actor: current_actor),
                filename: "<%= plural_name %>-#{Date.current}.csv", type: "text/csv"
    end

    # Datatable bulk actions on the selected ids — each is policy-checked per
    # record and tenant-scoped (Loam::Bulk). Zero selection is a no-op.
    def bulk
      ids = Array(params[:ids])
      case params[:bulk_action]
      when "soft_delete"
        count = Loam::Bulk.soft_delete(<%= class_name %>, ids)
        redirect_to polymorphic_path([:admin, <%= class_name %>]), notice: "Deleted #{count} record(s)."
      when "set_field"
        count = Loam::Bulk.set_field(<%= class_name %>, ids, field: params[:field], value: params[:value])
        redirect_to polymorphic_path([:admin, <%= class_name %>]), notice: "Updated #{count} record(s)."
      when "export"
        require_role!(:manager)  # same gate as the dedicated export action
        send_data Loam::Export.csv(Loam::Bulk.selected(<%= class_name %>, ids), actor: current_actor),
                  filename: "<%= plural_name %>-selected.csv", type: "text/csv"
      else
        redirect_to polymorphic_path([:admin, <%= class_name %>]), alert: "Unknown bulk action."
      end
    end

    # The recycle bin: only_deleted stays tenant-scoped, so this never shows
    # another tenant's deleted rows.
    def deleted
      authorize!(policy_for(<%= class_name %>.new), :read?)
      scope = <%= class_name %>.only_deleted.order(deleted_at: :desc, id: :desc)
      @records, @page, @has_next = paginate(scope)
    end

    def show
      authorize!(policy_for(@record), :read?)
    end

    def new
      @record = <%= class_name %>.new
      authorize!(policy_for(@record), :create?)
    end

    def create
      @record = <%= class_name %>.new
      policy = policy_for(@record)
      authorize!(policy, :create?)
      @record.assign_attributes(permitted_params(policy))
      assign_custom_fields!(@record, params, policy)
      attach_files!(@record, policy)

      if @record.save
        redirect_to [:admin, @record]
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize!(policy_for(@record), :update?)
      # Take the advisory lock (courtesy) or learn who holds it, for the banner.
      @lock = Loam::RecordLocks.acquire(@record, by: current_actor) || Loam::RecordLocks.active_lock(@record)
    end

    def update
      policy = policy_for(@record)
      authorize!(policy, :update?)
      assign_custom_fields!(@record, params, policy)
      attach_files!(@record, policy)

      if @record.update(permitted_params(policy))
        Loam::RecordLocks.release(@record, by: current_actor)
        redirect_to [:admin, @record]
      else
        render :edit, status: :unprocessable_entity
      end
    rescue ActiveRecord::StaleObjectError
      # Someone saved between open and submit — show the diff, reload fresh, retry.
      stale_conflict!(@record, FIELDS)
      @lock = Loam::RecordLocks.acquire(@record, by: current_actor) || Loam::RecordLocks.active_lock(@record)
      render :edit, status: :conflict
    end

    # Delete hides, it does not erase — the button is undoable. Reach for the
    # model's `destroy` only when a row must genuinely leave the database.
    def destroy
      authorize!(policy_for(@record), :destroy?)
      @record.soft_delete!
      Loam::RecordLocks.release(@record, by: current_actor)
      redirect_to [:admin, <%= class_name %>], notice: "<%= human_name %> deleted. Restore it from the recycle bin."
    end

    # Restore looks through the deleted rows — the default scope hides them, so a
    # plain find would 404 on the record we are trying to bring back.
    def restore
      @record = <%= class_name %>.with_deleted.find(params[:id])
      authorize!(policy_for(@record), :update?)
      @record.restore!
      redirect_to [:deleted, :admin, <%= class_name %>], notice: "<%= human_name %> restored."
    end

    private

    def set_record
      @record = <%= class_name %>.find(params[:id])
    end

    # The same filtered/perspective/search scope the index shows — reused by
    # export so the CSV matches what the manager is looking at.
    def index_scope
      scope = <%= class_name %>.order(created_at: :desc, id: :desc)
      perspective = Loam::Perspectives.resolve("<%= class_name %>", user: current_actor, id: params[:perspective_id])
      scope = perspective.apply(scope) if perspective
<% if searchable_attributes.any? -%>
      scope = scope.search(params[:q])
<% end -%>
      apply_custom_field_filter(scope)
    end

    # A custom-field filter routed through the read-model index
    # (Loam::CustomFieldIndex) — index-backed, not a JSON scan. An unknown field
    # is ignored rather than raising.
    def apply_custom_field_filter(scope)
      return scope if params[:cf_field].blank?

      scope.merge(Loam::CustomFieldIndex.filter(<%= class_name %>, params[:cf_field], params[:cf_op].presence || "eq", params[:cf_value]))
    rescue Loam::Error
      scope
    end

    # Field-level enforcement: the permit list comes from the policy, so a
    # role without write access to a field cannot smuggle it in via params.
    # lock_version rides outside the policy filter — it is optimistic-locking
    # plumbing, and a forged value just produces a harmless conflict.
    def permitted_params(policy)
      params.require(:<%= singular_name %>).permit(*policy.permitted_fields(FIELDS), :lock_version)
    end
  end
end
