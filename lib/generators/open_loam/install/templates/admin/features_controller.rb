module Admin
  # Feature flags (Loam::Features). Structural and privileged, so manager-only,
  # like Settings. Everything routes through Loam::Features; the admin toggles
  # the CURRENT tenant's override, and Reset drops it back to the declared /
  # global state. Global (app-wide) flips are a deploy concern, not this screen.
  class FeaturesController < BaseController
    before_action { require_role!(:manager) }

    def index
      @flags = Loam::Features.declared.map do |name|
        {
          name: name,
          on: Loam::Features.on?(name),
          overridden: Loam::Features.overridden?(name),
          description: Loam::Features.description(name)
        }
      end
    end

    def enable
      Loam::Features.enable(params[:name])
      redirect_to admin_features_path, notice: "#{params[:name]} enabled for this tenant."
    end

    def disable
      Loam::Features.disable(params[:name])
      redirect_to admin_features_path, notice: "#{params[:name]} disabled for this tenant."
    end

    def reset
      Loam::Features.reset(params[:name])
      redirect_to admin_features_path, notice: "#{params[:name]} reset to the default."
    end
  end
end
