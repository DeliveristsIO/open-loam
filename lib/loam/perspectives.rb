module Loam
  # Reading the saved views (Loam::Perspective) a user may see for an entity.
  #
  #   Loam::Perspectives.visible_to("Equipment", user: current_actor)   # pick list
  #   Loam::Perspectives.default_for("Equipment", user: current_actor)  # the applicable default
  #   Loam::Perspectives.resolve("Equipment", user:, id: params[:perspective_id])
  #
  # Every query is tenant-scoped by Loam::Perspective. The membership role used
  # for role-shared views is the user's role in the CURRENT tenant.
  module Perspectives
    class << self
      # The views this user may see for an entity: their own private ones, the
      # role-shared ones matching their membership role, and the tenant-wide
      # ones. Default(s) first, then by name. Named `visible_to` rather than
      # `for` so it does not read like Loam::Policy.for (which builds a policy).
      def visible_to(entity_type, user:)
        base = Loam::Perspective.where(entity_type: entity_type.to_s)
        role = membership_role(user)

        # Build the OR chain on UNORDERED relations — `.or` refuses to combine
        # relations that carry an order — then order once at the end.
        visible = base.where(visibility: "private", owner_id: user&.id)
                      .or(base.where(visibility: "tenant"))
        visible = visible.or(base.where(visibility: "role", role: role)) if role

        visible.order(is_default: :desc, name: :asc)
      end

      # The applicable default, most specific audience first: the user's own
      # private default, else a role default, else a tenant default, else nil.
      def default_for(entity_type, user:)
        defaults = visible_to(entity_type, user: user).select(&:is_default?)
        defaults.min_by { |perspective| VISIBILITY_PRIORITY.fetch(perspective.visibility, 9) }
      end

      # The view to apply for an index request: the one explicitly picked (if the
      # user may see it), otherwise the default. nil means "no saved view".
      def resolve(entity_type, user:, id: nil)
        # "none" is the picker's explicit "show everything" — it must bypass the
        # default, or a tenant default would be inescapable from the UI.
        return nil if id == "none"

        if id.present?
          picked = visible_to(entity_type, user: user).find_by(id: id)
          return picked if picked
        end

        default_for(entity_type, user: user)
      end

      private

      VISIBILITY_PRIORITY = { "private" => 0, "role" => 1, "tenant" => 2 }.freeze

      def membership_role(user)
        return nil unless user

        Loam::Membership.find_by(user_id: user.id)&.role
      end
    end
  end
end
