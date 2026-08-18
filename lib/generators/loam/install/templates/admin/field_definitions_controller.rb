module Admin
  # Manages Loam::FieldDefinition records: the "migration-free field" screen.
  # Structural, not per-entity — gated on the manager role rather than a
  # generated entity policy, since a field definition applies to a whole
  # entity_type, not one record.
  class FieldDefinitionsController < BaseController
    before_action { require_role!(:manager) }
    before_action :set_record, only: %i[destroy]

    def index
      @entity_type = params[:entity_type]
      @records = Loam::FieldDefinition.order(:entity_type, :name)
      @records = @records.where(entity_type: @entity_type) if @entity_type.present?
    end

    def new
      @record = Loam::FieldDefinition.new(entity_type: params[:entity_type])
    end

    def create
      @record = Loam::FieldDefinition.new(permitted_params)
      @record.writable_roles = parse_roles(params.dig(:field_definition, :writable_roles))

      if @record.save
        redirect_to admin_field_definitions_path(entity_type: @record.entity_type)
      else
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      entity_type = @record.entity_type
      @record.destroy!
      redirect_to admin_field_definitions_path(entity_type: entity_type)
    end

    private

    def set_record
      @record = Loam::FieldDefinition.find(params[:id])
    end

    def permitted_params
      params.require(:field_definition).permit(:entity_type, :name, :field_type)
    end

    def parse_roles(raw)
      raw.to_s.split(",").map(&:strip).reject(&:blank?)
    end
  end
end
