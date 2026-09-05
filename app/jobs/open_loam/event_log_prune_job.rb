module OpenLoam
  # Enforces the event log's retention window (see OpenLoam::EventLog.prune).
  # Capture is on by default and captures everything, so without this the log
  # grows without bound.
  #
  # Registered per-tenant via OpenLoam::Scheduler (see OpenLoam::Engine), so
  # `sync_tenant` materializes a schedule row per tenant and the scheduler
  # allowlist already covers the class. Tenant-scoped: the prune runs inside one
  # tenant, so there is no cross-tenant delete.
  class EventLogPruneJob < ActiveJob::Base
    queue_as :default

    def perform(tenant_id: nil)
      tenant = OpenLoam::Tenant.find_by(id: tenant_id)
      return if tenant.nil?

      OpenLoam.as_tenant(tenant) { OpenLoam::EventLog.prune }
    end
  end
end
