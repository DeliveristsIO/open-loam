module Loam
  # Periodic durability sweep: re-enqueues due-but-undelivered event deliveries
  # whose accelerator job was lost (worker crash, dropped message, an async
  # adapter racing the creating transaction). This — not perform_later at publish
  # — is what makes persistent delivery durable.
  #
  # Registered per-tenant via Loam::Scheduler (see Loam::Engine), so `sync_tenant`
  # materializes a schedule row per tenant and the scheduler allowlist already
  # covers the class. Tenant-scoped: the scheduler enqueues it with tenant_id and
  # the sweep runs inside that tenant, so there is no cross-tenant scan.
  class EventRedeliverySweepJob < ActiveJob::Base
    queue_as :default

    def perform(tenant_id: nil)
      tenant = Loam::Tenant.find_by(id: tenant_id)
      return if tenant.nil?

      Loam.as_tenant(tenant) { Loam::DurableEvents.redeliver_stuck }
    end
  end
end
