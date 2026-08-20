module Admin
  class EquipmentController < BaseController
    FIELDS = %i[name daily_rate status].freeze

    before_action :set_record, only: %i[show edit update destroy]

    def index
      # id breaks ties on created_at, so a record can never slip between pages.
      scope = Equipment.order(created_at: :desc, id: :desc)
      scope = scope.search(params[:q])

      @records, @page, @has_next = paginate(scope)
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
    end

    def update
      policy = policy_for(@record)
      authorize!(policy, :update?)
      assign_custom_fields!(@record, params, policy)
      attach_files!(@record, policy)

      if @record.update(permitted_params(policy))
        redirect_to [:admin, @record]
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Delete hides, it does not erase — the button is undoable. Reach for the
    # model's `destroy` only when a row must genuinely leave the database.
    def destroy
      authorize!(policy_for(@record), :destroy?)
      @record.soft_delete!
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

    # Field-level enforcement: the permit list comes from the policy, so a
    # role without write access to a field cannot smuggle it in via params.
    def permitted_params(policy)
      params.require(:equipment).permit(*policy.permitted_fields(FIELDS))
    end
  end
end
