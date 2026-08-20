module Admin
  class CustomersController < BaseController
    FIELDS = %i[name email tax_id].freeze

    before_action :set_record, only: %i[show edit update destroy]

    def index
      # id breaks ties on created_at, so a record can never slip between pages.
      scope = Customer.order(created_at: :desc, id: :desc)
      scope = scope.search(params[:q])

      @records, @page, @has_next = paginate(scope)
    end

    # The recycle bin: only_deleted stays tenant-scoped, so this never shows
    # another tenant's deleted rows.
    def deleted
      authorize!(policy_for(Customer.new), :read?)
      scope = Customer.only_deleted.order(deleted_at: :desc, id: :desc)
      @records, @page, @has_next = paginate(scope)
    end

    def show
      authorize!(policy_for(@record), :read?)
    end

    def new
      @record = Customer.new
      authorize!(policy_for(@record), :create?)
    end

    def create
      @record = Customer.new
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
      redirect_to [:admin, Customer], notice: "Customer deleted. Restore it from the recycle bin."
    end

    # Restore looks through the deleted rows — the default scope hides them, so a
    # plain find would 404 on the record we are trying to bring back.
    def restore
      @record = Customer.with_deleted.find(params[:id])
      authorize!(policy_for(@record), :update?)
      @record.restore!
      redirect_to [:deleted, :admin, Customer], notice: "Customer restored."
    end

    private

    def set_record
      @record = Customer.find(params[:id])
    end

    # Field-level enforcement: the permit list comes from the policy, so a
    # role without write access to a field cannot smuggle it in via params.
    def permitted_params(policy)
      params.require(:customer).permit(*policy.permitted_fields(FIELDS))
    end
  end
end
