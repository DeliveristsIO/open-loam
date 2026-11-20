# lib/open_loam/webhooks/http_transport.rb
require "net/http"
require "timeout"

module OpenLoam
  module Webhooks
    # The only code that opens a socket for a webhook. Connects to the address
    # OutboundUrl just vetted (no DNS rebinding window), never follows a
    # redirect (a 3xx is the answer), and reads at most EXCERPT_BYTES of the
    # response so a hostile receiver cannot make us buffer a large body.
    #
    # The per-operation timeouts (open/read/write) do not bound a receiver that
    # trickles one byte per read_timeout, so the whole request also runs under
    # an overall deadline of 3 x Webhooks.timeout (30 s by default). Keep that
    # deadline below Webhooks.stuck_after (5 min by default), or the sweep may
    # resend a delivery that is still in flight.
    module HttpTransport
      class ExcerptComplete < StandardError; end

      module_function

      def post(url, body:, headers:, timeout:)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        code = nil
        retry_after = nil
        excerpt = +""
        # Timeout::Error is a StandardError: Webhooks.deliver retries it as a
        # network error, counted against the endpoint like any other.
        Timeout.timeout(timeout * 3) do
          # DNS resolution is inside the deadline too.
          uri, address = OpenLoam::OutboundUrl.resolve!(url, require_https: Webhooks.require_https?,
                                                             ports: Webhooks.allowed_ports)
          # nil proxy: an http_proxy in ENV must not bypass the pinned address.
          http = Net::HTTP.new(uri.host, uri.port, nil)
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

        Response.new(code: code, headers: { "retry-after" => retry_after }, excerpt: safe_excerpt(excerpt),
                     duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
      end

      # Always valid UTF-8 without NUL (Postgres rejects both in a text column,
      # and a row that cannot be saved would be resent forever), at most
      # EXCERPT_BYTES. Scrubbing can grow the string (one bad byte becomes a
      # 3-byte U+FFFD), so it is cut again, dropping any split character.
      def safe_excerpt(raw)
        text = raw.byteslice(0, EXCERPT_BYTES).to_s.force_encoding(Encoding::UTF_8).scrub.delete("\u0000")
        text = text.byteslice(0, EXCERPT_BYTES).scrub("") if text.bytesize > EXCERPT_BYTES
        text
      end
    end
  end
end
