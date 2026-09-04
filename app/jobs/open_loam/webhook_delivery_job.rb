require "net/http"
require "openssl"

module OpenLoam
  # Delivers one event to one endpoint. Inherits ActiveJob::Base rather than
  # the host app's ApplicationJob: the gem must not depend on a class the app
  # owns and may have configured for its own retries.
  #
  # Signing: the receiver recomputes HMAC-SHA256 of the exact body with the
  # endpoint's secret and compares it to X-OpenLoam-Signature. Body building and
  # signing are class methods so both sides — and the tests — can call them
  # without a network.
  class WebhookDeliveryJob < ActiveJob::Base
    queue_as :default

    TIMEOUT_SECONDS = 5

    def self.body_for(event_name, payload, tenant_id)
      JSON.generate(event: event_name, payload: payload, tenant_id: tenant_id)
    end

    def self.signature(secret, body)
      "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret.to_s, body)}"
    end

    def perform(tenant_id, endpoint_id, event_name, payload)
      tenant = OpenLoam::Tenant.find_by(id: tenant_id)
      return if tenant.nil?

      OpenLoam.as_tenant(tenant) do
        endpoint = OpenLoam::WebhookEndpoint.find_by(id: endpoint_id)
        # The endpoint may have been deleted or switched off between enqueue
        # and delivery — that is an answer, not an error.
        next if endpoint.nil? || !endpoint.active?

        deliver(endpoint, self.class.body_for(event_name, payload, tenant_id), event_name)
      end
    end

    private

    def deliver(endpoint, body, event_name)
      uri = URI.parse(endpoint.url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = TIMEOUT_SECONDS
      http.read_timeout = TIMEOUT_SECONDS

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["X-OpenLoam-Event"] = event_name
      request["X-OpenLoam-Signature"] = self.class.signature(endpoint.secret, body)
      request.body = body

      http.request(request)
    end
  end
end
