module Admin
  # Managing saved views (Loam::Perspective) for an entity. A view is CREATED by
  # "save current view" on the entity index (capturing the live filters/sort); it
  # starts private, owned by you. Here you rename it, widen its audience, make it
  # the default, or delete it.
  #
  # Who may manage a view: its owner always; a manager for role/tenant-visibility
  # ones. A private view of someone else's is invisible here by construction
  # (Loam::Perspectives.visible_to never returns it).
  class PerspectivesController < BaseController
    before_action :set_perspective, only: %i[update destroy set_default]
    before_action :authorize_manage!, only: %i[update destroy set_default]

    rescue_from ActiveRecord::StaleObjectError do
      redirect_to admin_perspectives_path(entity_type: params[:entity_type]),
                  alert: "Someone else changed that view; nothing was saved. Reload and try again."
    end

    def index
      @entity_type = params[:entity_type].to_s
      @perspectives = Loam::Perspectives.visible_to(@entity_type, user: current_actor)
    end

    # From the entity index: save the CURRENT filters/sort as a new private view.
    def create
      perspective = Loam::Perspective.create!(
        entity_type: params[:entity_type].to_s,
        name: params[:name].presence || "Saved view",
        visibility: "private",
        owner_id: current_actor.id,
        config: captured_config
      )
      redirect_to index_path_for(perspective), notice: "Saved the current view."
    end

    def update
      # Widening a private view to role/tenant is a manager action; and changing
      # the audience clears the default flag so it is re-chosen deliberately.
      attributes = perspective_params
      if attributes[:visibility].present? && attributes[:visibility] != @perspective.visibility
        raise Loam::NotAuthorizedError if attributes[:visibility] != "private" && current_role != :manager

        attributes[:is_default] = false
      end

      if @perspective.update(attributes)
        redirect_to index_path_for(@perspective), notice: "View updated."
      else
        redirect_to index_path_for(@perspective), alert: @perspective.errors.full_messages.to_sentence
      end
    end

    def set_default
      @perspective.make_default!
      redirect_to index_path_for(@perspective), notice: "Default view set."
    end

    def destroy
      perspective = @perspective
      perspective.destroy!
      redirect_to index_path_for(perspective), notice: "View deleted."
    end

    private

    def set_perspective
      @perspective = Loam::Perspective.find(params[:id])
    end

    def authorize_manage!
      raise Loam::NotAuthorizedError unless can_manage?(@perspective)
    end

    # Owner always; a manager for shared (role/tenant) views. A private view of
    # another user is never even loaded here, so this only guards shared ones.
    def can_manage?(perspective)
      perspective.owner_id == current_actor.id || (perspective.visibility != "private" && current_role == :manager)
    end

    def perspective_params
      params.require(:perspective).permit(:name, :visibility, :role)
    end

    # Config is built from the index's live params, never from trusted raw JSON.
    # apply() whitelists columns regardless, so nothing here can smuggle a filter
    # onto a plumbing column.
    def captured_config
      {
        "filters" => { "q" => params[:q].presence }.compact,
        "sort" => { "field" => params[:sort_field].presence, "dir" => params[:sort_dir].presence }.compact
      }.reject { |_, value| value.blank? }
    end

    def index_path_for(perspective)
      admin_perspectives_path(entity_type: perspective.entity_type)
    end
  end
end
