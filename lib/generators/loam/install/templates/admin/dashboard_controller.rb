module Admin
  class DashboardController < BaseController
    def index
      @audit_records = Loam::AuditRecord.order(created_at: :desc).limit(50)
    end
  end
end
