module Admin
  class DashboardController < BaseController
    def index
      @audit_records = Loam::AuditRecord.order(created_at: :desc).limit(50)
    end

    # A capability behind a flag: only tenants with beta_dashboard turned on can
    # reach it. require_feature! raises Loam::FeatureDisabledError → 404 when off.
    def beta
      require_feature!(:beta_dashboard)
    end
  end
end
