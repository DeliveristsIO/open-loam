module Admin
  # Dashboard settings (OpenLoam::DashboardWidget) — manager-only. Choose which
  # registered widgets appear and in what order for this tenant.
  class DashboardWidgetsController < BaseController
    before_action { require_role!(:manager) }

    def index
      @registered = OpenLoam::Widgets.registered
      @config = OpenLoam::DashboardWidget.all.index_by(&:widget_key)
    end

    def update
      OpenLoam::Widgets.keys.each do |key|
        attrs = params.dig(:widgets, key) || {}
        row = OpenLoam::DashboardWidget.find_or_initialize_by(widget_key: key)
        row.active = attrs[:active] == "1"
        row.position = attrs[:position].to_i
        row.save!
      end
      redirect_to admin_root_path, notice: "Dashboard updated."
    end
  end
end
