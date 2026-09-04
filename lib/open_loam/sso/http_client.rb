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
        uri = URI(url)
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{bearer}" if bearer
        parse(perform(uri, request))
      end

      def post_form(url, params)
        uri = URI(url)
        request = Net::HTTP::Post.new(uri)
        request.set_form_data(params)
        request["Accept"] = "application/json"
        parse(perform(uri, request))
      end

      def perform(uri, request)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
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
