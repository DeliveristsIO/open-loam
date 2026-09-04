module Api
  # JSON for Lead. Same rules as the admin screen, same policy:
  # the token's user is the actor, so a role that may not write a field cannot
  # write it here either — `permitted_fields` drops it from the permit list.
  class LeadsController < BaseController
    FIELDS = %i[company_id source value state].freeze

    before_action :set_record, only: %i[show update destroy]

    def index
      records = Lead.order(created_at: :desc).to_a
      enriched = OpenLoam::Enrichers.enrich_many(records)   # one batched pass, no N+1
      render json: records.map { |record| entity_json(record, enrichments: enriched[record.id]) }
    end

    def show
      authorize!(policy_for(@record), :read?)
      render json: entity_json(@record)
    end

    def create
      @record = Lead.new
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

    # Soft-delete here too, so DELETE is the ONE way to delete across both
    # surfaces: the record is hidden and recoverable, not erased. The recycle
    # bin itself is an admin concern; the API just gets the safer default.
    def destroy
      authorize!(policy_for(@record), :destroy?)
      @record.soft_delete!
      head :no_content
    end

    private

    def set_record
      @record = Lead.find(params[:id])
    end

    def permitted_params(policy)
      params.require(:lead).permit(*policy.permitted_fields(FIELDS))
    end
  end
end
