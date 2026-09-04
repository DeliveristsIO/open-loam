module Admin
  class DashboardController < BaseController
    def index
      # Configurable, role-visible widgets (OpenLoam::Dashboard) — a raising widget
      # is isolated into an error tile, never breaking the page. Register your
      # own with OpenLoam::Widgets.register; arrange them under Dashboard settings.
      @widgets = OpenLoam::Dashboard.for(actor: current_actor, role: current_role)
    end
  end
end
