module Admin
  class EquipmentController < BaseController
    FIELDS = %i[name daily_rate status].freeze

    before_action :set_record, only: %i[show edit update destroy]

    def index
      @perspective = Loam::Perspectives.resolve("Equipment", user: current_actor, id: params[:perspective_id])
      @perspectives = Loam::Perspectives.visible_to("Equipment", user: current_actor)
      @records, @page, @has_next = paginate(index_scope)
    end

    # CSV of the CURRENT filtered/perspective view — manager-only, policy- and
    # encryption-aware (Loam::Export).
    def export
      require_role!(:manager)
      send_data Loam::Export.csv(index_scope, actor: current_actor),
                filename: "equipment-#{Date.current}.csv", type: "text/csv"
    end

    # Datatable bulk actions on the selected ids — each is policy-checked per
    # record and tenant-scoped (Loam::Bulk).
    def bulk
      ids = Array(params[:ids])
      case params[:bulk_action]
      when "soft_delete"
        count = Loam::Bulk.soft_delete(Equipment, ids)
        redirect_to admin_equipment_index_path, notice: "Deleted #{count} record(s)."
      when "set_status"
        count = Loam::Bulk.set_field(Equipment, ids, field: "status", value: params[:value])
        redirect_to admin_equipment_index_path, notice: "Updated #{count} record(s)."
      when "export"
        require_role!(:manager)  # same gate as the dedicated export action
        send_data Loam::Export.csv(Loam::Bulk.selected(Equipment, ids), actor: current_actor),
                  filename: "equipment-selected.csv", type: "text/csv"
      else
        redirect_to admin_equipment_index_path, alert: "Unknown bulk action."
      end
    end

    # The recycle bin: only_deleted stays tenant-scoped, so this never shows
    # another tenant's deleted rows.
    def deleted
      authorize!(policy_for(Equipment.new), :read?)
      scope = Equipment.only_deleted.order(deleted_at: :desc, id: :desc)
      @records, @page, @has_next = paginate(scope)
    end

    def show
      authorize!(policy_for(@record), :read?)
    end

    def new
      @record = Equipment.new
      authorize!(policy_for(@record), :create?)
    end

    def create
      @record = Equipment.new
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
      redirect_to [:admin, Equipment], notice: "Equipment deleted. Restore it from the recycle bin."
    end

    # Stands in for an AI agent proposing a price change: instead of applying it,
    # STAGE it as a Loam::PendingAction for a manager to approve. This is the
    # confirm-mode pattern an MCP tool would follow — nothing is mutated here.
    def propose_price
      set_record
      Loam::PendingActions.stage(
        summary: "Raise #{@record.name}'s daily rate to #{params[:daily_rate]}",
        on: @record,
        action: :update,
        changes: { daily_rate: params[:daily_rate] }
      )
      redirect_to [:admin, @record], notice: "Proposed change staged for approval — see Approvals."
    end

    # Restore looks through the deleted rows — the default scope hides them, so a
    # plain find would 404 on the record we are trying to bring back.
    def restore
      @record = Equipment.with_deleted.find(params[:id])
      authorize!(policy_for(@record), :update?)
      @record.restore!
      redirect_to [:deleted, :admin, Equipment], notice: "Equipment restored."
    end

    private

    def set_record
      @record = Equipment.find(params[:id])
    end

    # The same filtered/perspective/search scope the index shows — reused by
    # export so the CSV matches what the manager is looking at.
    def index_scope
      scope = Equipment.order(created_at: :desc, id: :desc)
      perspective = Loam::Perspectives.resolve("Equipment", user: current_actor, id: params[:perspective_id])
      scope = perspective.apply(scope) if perspective
      scope.search(params[:q])
    end

    # Field-level enforcement: the permit list comes from the policy, so a
    # role without write access to a field cannot smuggle it in via params.
    # lock_version rides outside the policy filter — it is optimistic-locking
    # plumbing, not a business field. A forged value just produces a conflict
    # (UPDATE WHERE lock_version = garbage → 0 rows → StaleObjectError), so
    # permitting it is safe.
    def permitted_params(policy)
      params.require(:equipment).permit(*policy.permitted_fields(FIELDS), :lock_version)
    end
  end
end
