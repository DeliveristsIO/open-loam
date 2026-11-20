# lib/open_loam/webhooks/http_transport.rb
require "net/http"

module OpenLoam
  module Webhooks
    # The only code that opens a socket for a webhook. Connects to the address
    # OutboundUrl just vetted (no DNS rebinding window), never follows a
    # redirect (a 3xx is the answer), and reads at most EXCERPT_BYTES of the
    # response so a hostile receiver cannot make us buffer a large body.
    module HttpTransport
      class ExcerptComplete < StandardError; end

      module_function

      def post(url, body:, headers:, timeout:)
        uri, address = OpenLoam::OutboundUrl.resolve!(url, require_https: Webhooks.require_https?,
                                                           ports: Webhooks.allowed_ports)
        http = Net::HTTP.new(uri.host, uri.port)
        http.ipaddr = address
        http.use_ssl = uri.scheme == "https"
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER if http.use_ssl?
        http.open_timeout = timeout
        http.read_timeout = timeout
        http.write_timeout = timeout

        request = Net::HTTP::Post.new(uri.request_uri)
        headers.each { |name, value| request[name] = value }
        request["Accept-Encoding"] = "identity" # a compressed body could inflate past the excerpt cap
        request.body = body

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        code = nil
        retry_after = nil
        excerpt = +""
        begin
          http.start do |connection|
            connection.request(request) do |response|
              code = response.code.to_i
              retry_after = response["retry-after"]
              response.read_body do |chunk|
                excerpt << chunk
                raise ExcerptComplete if excerpt.bytesize >= EXCERPT_BYTES
              end
            end
          end
        rescue ExcerptComplete
          # Enough of the body; the connection is closed by http.start's ensure.
        end

        Response.new(code: code, headers: { "retry-after" => retry_after },
                     excerpt: excerpt.byteslice(0, EXCERPT_BYTES).to_s.scrub,
                     duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
      end
    end
  end
end
