module Loam
  # Resolves the admin dashboard for the current tenant/actor: the ordered,
  # role-visible, computed widgets to show. Uses the tenant's configured
  # Loam::DashboardWidget rows (a manager arranges them); falls back to every
  # registered widget in registration order when the tenant has configured none,
  # so the dashboard is useful out of the box.
  module Dashboard
    module_function

    def for(actor:, role:)
      configured = Loam::DashboardWidget.active.ordered.pluck(:widget_key)
      keys = configured.presence || Loam::Widgets.keys

      keys.filter_map { |key| Loam::Widgets.resolve(key, actor: actor, role: role) }
    end
  end
end
