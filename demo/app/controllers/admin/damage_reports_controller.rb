module Admin
  class DamageReportsController < BaseController
    FIELDS = %i[equipment_id description approved].freeze

    before_action :set_record, only: %i[show edit update destroy]

    def index
      authorize!(policy_for(DamageReport.new), :read?)
      # id breaks ties on created_at, so a record can never slip between pages.
      scope = DamageReport.order(created_at: :desc, id: :desc)
      scope = scope.search(params[:q])

      @records, @page, @has_next = paginate(scope)
    end

    # The recycle bin: only_deleted stays tenant-scoped, so this never shows
    # another tenant's deleted rows.
    def deleted
      authorize!(policy_for(DamageReport.new), :read?)
      scope = DamageReport.only_deleted.order(deleted_at: :desc, id: :desc)
      @records, @page, @has_next = paginate(scope)
    end

    def show
      authorize!(policy_for(@record), :read?)
    end

    def new
      @record = DamageReport.new
      authorize!(policy_for(@record), :create?)
    end

    def create
      @record = DamageReport.new
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
      @lock = OpenLoam::RecordLocks.acquire(@record, by: current_actor) || OpenLoam::RecordLocks.active_lock(@record)
    end

    def update
      policy = policy_for(@record)
      authorize!(policy, :update?)
      assign_custom_fields!(@record, params, policy)
      attach_files!(@record, policy)

      if @record.update(permitted_params(policy))
        OpenLoam::RecordLocks.release(@record, by: current_actor)
        redirect_to [:admin, @record]
      else
        render :edit, status: :unprocessable_entity
      end
    rescue ActiveRecord::StaleObjectError
      stale_conflict!(@record, FIELDS)
      @lock = OpenLoam::RecordLocks.acquire(@record, by: current_actor) || OpenLoam::RecordLocks.active_lock(@record)
      render :edit, status: :conflict
    end

    # Delete hides, it does not erase — the button is undoable. Reach for the
    # model's `destroy` only when a row must genuinely leave the database.
    def destroy
      authorize!(policy_for(@record), :destroy?)
      @record.soft_delete!
      OpenLoam::RecordLocks.release(@record, by: current_actor)
      redirect_to [:admin, DamageReport], notice: "Damage report deleted. Restore it from the recycle bin."
    end

    # Restore looks through the deleted rows — the default scope hides them, so a
    # plain find would 404 on the record we are trying to bring back.
    def restore
      @record = DamageReport.with_deleted.find(params[:id])
      authorize!(policy_for(@record), :update?)
      @record.restore!
      redirect_to [:deleted, :admin, DamageReport], notice: "Damage report restored."
    end

    private

    def set_record
      @record = DamageReport.find(params[:id])
    end

    # Field-level enforcement: the permit list comes from the policy, so a
    # role without write access to a field cannot smuggle it in via params.
    def permitted_params(policy)
      params.require(:damage_report).permit(*policy.permitted_fields(FIELDS), :lock_version)
    end
  end
end
