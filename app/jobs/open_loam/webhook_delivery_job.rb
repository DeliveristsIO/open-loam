require "net/http"
require "openssl"

module OpenLoam
  # Runs one attempt for one ledger row (OpenLoam::WebhookDelivery). Inherits
  # ActiveJob::Base rather than the host's ApplicationJob, and keeps no retry
  # state: OpenLoam::Webhooks.deliver moves the row and schedules the next try.
  #
  # The 4-argument form is what 0.3.0 enqueued (endpoint id, event, payload); a
  # job still in the queue at upgrade time becomes a ledger row and is delivered.
  class WebhookDeliveryJob < ActiveJob::Base
    queue_as :default

    # Frozen (BACKWARD_COMPATIBILITY.md §6): the default body and the v1 signature.
    def self.body_for(event_name, payload, tenant_id)
      JSON.generate(event: event_name, payload: payload, tenant_id: tenant_id)
    end

    def self.signature(secret, body)
      "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret.to_s, body)}"
    end

    def perform(tenant_id, delivery_id, legacy_event_name = nil, legacy_payload = nil)
      tenant = OpenLoam::Tenant.find_by(id: tenant_id)
      return if tenant.nil?

      OpenLoam.as_tenant(tenant) do
        delivery =
          if legacy_event_name
            endpoint = OpenLoam::WebhookEndpoint.find_by(id: delivery_id)
            next if endpoint.nil? || !endpoint.active?

            endpoint.deliveries.create!(event_id: SecureRandom.uuid, event_name: legacy_event_name.to_s,
                                        payload: legacy_payload || {})
          else
            OpenLoam::WebhookDelivery.find_by(id: delivery_id)
          end
        # Not visible yet (the creating transaction has not committed) or gone:
        # the sweep covers the first case.
        next if delivery.nil?

        OpenLoam::Webhooks.deliver(delivery)
      end
    end
  end
end
