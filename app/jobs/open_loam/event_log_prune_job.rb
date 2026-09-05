module OpenLoam
  # Enforces the event log's retention window (OpenLoam::EventLog.prune).
  # Registered per-tenant in OpenLoam::Engine, so it runs inside one tenant and
  # never deletes across the boundary.
  class EventLogPruneJob < ActiveJob::Base
    queue_as :default

    def perform(tenant_id: nil)
      tenant = OpenLoam::Tenant.find_by(id: tenant_id)
      return if tenant.nil?

      OpenLoam.as_tenant(tenant) { OpenLoam::EventLog.prune }
    end
  end
end
