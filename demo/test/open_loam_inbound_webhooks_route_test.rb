require "test_helper"

# The public route/controller wiring for L-710: POST /webhooks/:token maps the
# OpenLoam::InboundWebhooks result to a bare HTTP status and never leaks the tenant
# context it established into the next request.
class OpenLoamInboundWebhooksRouteTest < ActionDispatch::IntegrationTest
  SECRET = "route-secret".freeze

  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Branch", slug: "warsaw-inbound-route")
    @source = OpenLoam.as_tenant(@warsaw) do
      OpenLoam::InboundWebhookSource.create!(name: "Acme", secret: SECRET, event_name: "demo.inbound.received")
    end
  end

  def sig(body) = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", SECRET, body)

  test "POST /webhooks/:token verifies, 202s, and resets tenant context afterward" do
    body = %({"id":9})
    post "/webhooks/#{@source.token}",
         params: body, headers: { "CONTENT_TYPE" => "application/json", "X-OpenLoam-Signature" => sig(body) }

    assert_response 202
    assert_nil OpenLoam::Current.tenant, "tenant context must not leak past the request"
    assert_equal 1, OpenLoam.as_tenant(@warsaw) { OpenLoam::InboundWebhookDelivery.count }
  end

  test "a forged signature 401s with an empty body" do
    body = %({"id":9})
    post "/webhooks/#{@source.token}",
         params: body, headers: { "CONTENT_TYPE" => "application/json", "X-OpenLoam-Signature" => "sha256=deadbeef" }

    assert_response 401
    assert_equal "", response.body
  end
end
