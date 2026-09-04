module Loam
  # A tenant's dashboard layout: which registered widgets appear, in what order.
  # A manager arranges these on the Dashboard settings screen; the dashboard
  # renders the active ones by position (see Loam::Dashboard). Tenant-scoped and
  # audited.
  class DashboardWidget < Loam::TenantRecord
    self.table_name = "loam_dashboard_widgets"

    include Loam::Auditable

    validates :widget_key, presence: true, uniqueness: { scope: :tenant_id }

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(:position, :id) }
  end
end
