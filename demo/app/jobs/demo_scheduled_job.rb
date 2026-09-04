# A demo recurring job: touch every piece of equipment in a tenant (a stand-in
# for real periodic work — a sync, a digest, a reindex). Scheduled per tenant,
# so it receives its tenant_id and re-establishes the tenant, like every OpenLoam job.
class DemoScheduledJob < ApplicationJob
  queue_as :default

  def perform(tenant_id:)
    tenant = OpenLoam::Tenant.find(tenant_id)
    OpenLoam.as_tenant(tenant) do
      Equipment.find_each(&:touch)
    end
  end
end
