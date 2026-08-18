module Admin
  class EquipmentController < BaseController
    FIELDS = %i[name daily_rate status].freeze

    before_action :set_record, only: %i[show edit update destroy]

    def index
      @records = Equipment.order(created_at: :desc)
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

    def destroy
      authorize!(policy_for(@record), :destroy?)
      @record.destroy!
      redirect_to [:admin, Equipment]
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
