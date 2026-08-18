module Api
  # JSON for <%= class_name %>. Same rules as the admin screen, same policy:
  # the token's user is the actor, so a role that may not write a field cannot
  # write it here either — `permitted_fields` drops it from the permit list.
  class <%= plural_name.camelize %>Controller < BaseController
    FIELDS = %i[<%= field_names.join(" ") %>].freeze

    before_action :set_record, only: %i[show update destroy]

    def index
      render json: <%= class_name %>.order(created_at: :desc).map { |record| entity_json(record) }
    end

    def show
      authorize!(policy_for(@record), :read?)
      render json: entity_json(@record)
    end

    def create
      @record = <%= class_name %>.new
      policy = policy_for(@record)
      authorize!(policy, :create?)
      @record.assign_attributes(permitted_params(policy))
      assign_custom_fields!(@record, params, policy)

      if @record.save
        render json: entity_json(@record), status: :created
      else
        render json: { errors: @record.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      policy = policy_for(@record)
      authorize!(policy, :update?)
      @record.assign_attributes(permitted_params(policy))
      assign_custom_fields!(@record, params, policy)

      if @record.save
        render json: entity_json(@record)
      else
        render json: { errors: @record.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      authorize!(policy_for(@record), :destroy?)
      @record.destroy!
      head :no_content
    end

    private

    def set_record
      @record = <%= class_name %>.find(params[:id])
    end

    def permitted_params(policy)
      params.require(:<%= singular_name %>).permit(*policy.permitted_fields(FIELDS))
    end
  end
end
