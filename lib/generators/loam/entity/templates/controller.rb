module Admin
  class <%= plural_name.camelize %>Controller < BaseController
    FIELDS = %i[<%= field_names.join(" ") %>].freeze

    before_action :set_record, only: %i[show edit update destroy]

    def index
      # id breaks ties on created_at, so a record can never slip between pages.
      scope = <%= class_name %>.order(created_at: :desc, id: :desc)
<% if searchable_attributes.any? -%>
      scope = scope.search(params[:q])
<% end -%>

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
      redirect_to [:admin, <%= class_name %>]
    end

    private

    def set_record
      @record = <%= class_name %>.find(params[:id])
    end

    # Field-level enforcement: the permit list comes from the policy, so a
    # role without write access to a field cannot smuggle it in via params.
    def permitted_params(policy)
      params.require(:<%= singular_name %>).permit(*policy.permitted_fields(FIELDS))
    end
  end
end
