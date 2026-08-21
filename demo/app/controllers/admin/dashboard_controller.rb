module Admin
  class DashboardController < BaseController
    def index
      # Configurable, role-visible widgets (Loam::Dashboard) — a raising widget
      # is isolated into an error tile, never breaking the page.
      @widgets = Loam::Dashboard.for(actor: current_actor, role: current_role)
    end

    # A capability behind a flag: only tenants with beta_dashboard turned on can
    # reach it. require_feature! raises Loam::FeatureDisabledError → 404 when off.
    def beta
      require_feature!(:beta_dashboard)
    end
  end
end
