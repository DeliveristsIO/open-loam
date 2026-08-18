module Loam
  # Domain events, delivered over HTTP to whoever asked for them.
  #
  # One global subscriber listens to every Loam event and, in the tenant the
  # event was published in, enqueues a delivery per matching active endpoint.
  # Matching happens at dispatch time rather than at subscribe time because
  # endpoints are data: a tenant can add one from the admin without a reboot.
  module Webhooks
    # Wired once from Loam::Engine. Idempotent: subscribing twice would deliver
    # every event twice.
    def self.subscribe!
      @subscription ||= Events.subscribe_all { |event_name, payload| dispatch(event_name, payload) }
    end

    # Runs inline in whatever published the event, so it stays cheap: one
    # query for the tenant's active endpoints, then the HTTP call is a job.
    def self.dispatch(event_name, payload)
      tenant = Tenant.find_by(id: payload[:tenant_id])
      return if tenant.nil?

      # Only JSON-safe primitives cross into the job — event payloads are ids
      # and scalars by convention, never records.
      deliverable = payload.transform_keys(&:to_s)

      Loam.as_tenant(tenant) do
        WebhookEndpoint.active.each do |endpoint|
          next unless endpoint.matches?(event_name)

          WebhookDeliveryJob.perform_later(tenant.id, endpoint.id, event_name, deliverable)
        end
      end
    end
  end
end
