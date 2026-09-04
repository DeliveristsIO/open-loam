module OpenLoam
  # Resolves the admin dashboard for the current tenant/actor: the ordered,
  # role-visible, computed widgets to show. Uses the tenant's configured
  # OpenLoam::DashboardWidget rows (a manager arranges them); falls back to every
  # registered widget in registration order when the tenant has configured none,
  # so the dashboard is useful out of the box.
  module Dashboard
    module_function

    def for(actor:, role:)
      configured = OpenLoam::DashboardWidget.active.ordered.pluck(:widget_key)
      keys = configured.presence || OpenLoam::Widgets.keys

      keys.filter_map { |key| OpenLoam::Widgets.resolve(key, actor: actor, role: role) }
    end
  end
end
