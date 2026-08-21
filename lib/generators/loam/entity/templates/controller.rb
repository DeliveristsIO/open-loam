module Admin
  class <%= plural_name.camelize %>Controller < BaseController
    FIELDS = %i[<%= field_names.join(" ") %>].freeze

    before_action :set_record, only: %i[show edit update destroy]

    def index
      # id breaks ties on created_at, so a record can never slip between pages.
      scope = <%= class_name %>.order(created_at: :desc, id: :desc)

      # Apply the picked (or default) saved view first; a live filter composes on top.
      @perspective = Loam::Perspectives.resolve("<%= class_name %>", user: current_actor, id: params[:perspective_id])
      scope = @perspective.apply(scope) if @perspective
<% if searchable_attributes.any? -%>
      scope = scope.search(params[:q])
<% end -%>

      @perspectives = Loam::Perspectives.visible_to("<%= class_name %>", user: current_actor)
      @records, @page, @has_next = paginate(scope)
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

    # Field-level enforcement: the permit list comes from the policy, so a
    # role without write access to a field cannot smuggle it in via params.
    def permitted_params(policy)
      params.require(:<%= singular_name %>).permit(*policy.permitted_fields(FIELDS))
    end
  end
end
