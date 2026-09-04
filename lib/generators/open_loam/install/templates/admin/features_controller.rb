module Admin
  # Feature flags (OpenLoam::Features). Structural and privileged, so manager-only,
  # like Settings. Everything routes through OpenLoam::Features; the admin toggles
  # the CURRENT tenant's override, and Reset drops it back to the declared /
  # global state. Global (app-wide) flips are a deploy concern, not this screen.
  class FeaturesController < BaseController
    before_action { require_role!(:manager) }

    def index
      @flags = OpenLoam::Features.declared.map do |name|
        {
          name: name,
          on: OpenLoam::Features.on?(name),
          overridden: OpenLoam::Features.overridden?(name),
          description: OpenLoam::Features.description(name)
        }
      end
    end

    def enable
      OpenLoam::Features.enable(params[:name])
      redirect_to admin_features_path, notice: "#{params[:name]} enabled for this tenant."
    end

    def disable
      OpenLoam::Features.disable(params[:name])
      redirect_to admin_features_path, notice: "#{params[:name]} disabled for this tenant."
    end

    def reset
      OpenLoam::Features.reset(params[:name])
      redirect_to admin_features_path, notice: "#{params[:name]} reset to the default."
    end
  end
end
