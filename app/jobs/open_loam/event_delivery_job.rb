module Loam
  # Runs one durable event delivery (Loam::DurableEvents). Inherits
  # ActiveJob::Base rather than the host app's ApplicationJob — the gem must not
  # depend on a class the app owns and may have configured for its own retries —
  # and carries the tenant explicitly (ActiveJob doesn't serialize Loam::Current).
  #
  # A missing row is an ANSWER, not an error: with an async queue adapter the job
  # can start before the creating transaction commits, so the row isn't visible
  # yet. The job no-ops; the redelivery sweep picks the row up once it commits.
  # Retry state lives in the ROW (Loam::DurableEvents.deliver), never here.
  class EventDeliveryJob < ActiveJob::Base
    queue_as :default

    def perform(tenant_id, delivery_id)
      tenant = Loam::Tenant.find_by(id: tenant_id)
      return if tenant.nil?

      Loam.as_tenant(tenant) do
        delivery = Loam::EventDelivery.find_by(id: delivery_id)
        return if delivery.nil? # not visible yet (txn race) or gone — the sweep covers it

        Loam::DurableEvents.deliver(delivery)
      end
    end
  end
end
