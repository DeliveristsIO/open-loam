# Public endpoint that receives webhooks FROM external systems at
# /webhooks/:token. No session, no bearer token: the HMAC signature is the auth
# (ActionController::API, so there is no CSRF to skip). All the verified,
# replay-resistant work lives in Loam::InboundWebhooks.ingest; this controller
# only maps its Result to an HTTP status and never leaks tenant context to the
# next request on this thread.
class InboundWebhooksController < ActionController::API
  def receive
    result = Loam::InboundWebhooks.ingest(
      token: params[:token], raw_body: request.raw_post, headers: request.headers
    )
    Rails.logger.info("[loam inbound] #{result.status} #{result.reason}") if result.status >= 400
    head result.status
  ensure
    Loam::Current.reset
  end
end
