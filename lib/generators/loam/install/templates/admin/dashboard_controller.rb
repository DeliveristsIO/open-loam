module Admin
  class DashboardController < BaseController
    def index
      # Configurable, role-visible widgets (Loam::Dashboard) — a raising widget
      # is isolated into an error tile, never breaking the page. Register your
      # own with Loam::Widgets.register; arrange them under Dashboard settings.
      @widgets = Loam::Dashboard.for(actor: current_actor, role: current_role)
    end
  end
end
