require "net/http"
require "json"

module OpenLoam
  module Sso
    # The one place SSO talks to the network — kept tiny and isolated so the rest
    # of the flow is pure. Only OpenLoam::Sso::OidcProvider uses it, and the test
    # suite injects a FakeProvider instead, so this is never exercised offline.
    module HttpClient
      module_function

      def get_json(url, bearer: nil)
        uri, address = checked(url)
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{bearer}" if bearer
        parse(perform(uri, address, request))
      end

      def post_form(url, params)
        uri, address = checked(url)
        request = Net::HTTP::Post.new(uri)
        request.set_form_data(params)
        request["Accept"] = "application/json"
        parse(perform(uri, address, request))
      end

      # The issuer is typed by a tenant manager, so these URLs are as untrusted
      # as a webhook endpoint's. https is mandatory here rather than merely
      # allowed: the client_secret and the code exchange travel over it.
      def checked(url)
        OpenLoam::OutboundUrl.resolve!(url, require_https: true)
      rescue OpenLoam::OutboundUrl::BlockedError => error
        raise OpenLoam::Sso::Error, "identity provider URL refused: #{error.message}"
      end

      def perform(uri, address, request)
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, ipaddr: address) do |http|
          http.request(request)
        end
      end

      def parse(response)
        unless response.is_a?(Net::HTTPSuccess)
          raise OpenLoam::Sso::Error, "identity provider returned #{response.code}"
        end

        JSON.parse(response.body)
      end
    end
  end
end
