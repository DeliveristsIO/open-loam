module OpenLoam
  # Finishes what a lost job left behind and prunes the ledger.
  #
  # With a tenant (how OpenLoam::Scheduler runs it): sweeps that tenant.
  # Without one (how a host's own cron runs it, e.g. Solid Queue recurring):
  # enqueues one tenant-scoped sweep per tenant that has work.
  class WebhookSweepJob < ActiveJob::Base
    queue_as :default

    def perform(tenant_id: nil)
      if tenant_id.nil?
        OpenLoam::Webhooks.tenant_ids_needing_sweep.each { |id| self.class.perform_later(tenant_id: id) }
        return
      end

      tenant = OpenLoam::Tenant.find_by(id: tenant_id)
      return if tenant.nil?

      OpenLoam.as_tenant(tenant) { OpenLoam::Webhooks.sweep }
    end
  end
end
