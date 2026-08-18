module Admin
  class DamageReportsController < BaseController
    FIELDS = %i[equipment_id description approved].freeze

    before_action :set_record, only: %i[show edit update destroy]

    def index
      # id breaks ties on created_at, so a record can never slip between pages.
      scope = DamageReport.order(created_at: :desc, id: :desc)
      scope = scope.search(params[:q])

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
      redirect_to [:admin, DamageReport]
    end

    private

    def set_record
      @record = DamageReport.find(params[:id])
    end

    # Field-level enforcement: the permit list comes from the policy, so a
    # role without write access to a field cannot smuggle it in via params.
    def permitted_params(policy)
      params.require(:damage_report).permit(*policy.permitted_fields(FIELDS))
    end
  end
end
