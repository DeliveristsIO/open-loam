require "ipaddr"
require "socket"
require "resolv"
require "uri"

module OpenLoam
  # Guard for URLs a TENANT supplies and the SERVER then fetches — webhook
  # endpoints and the SSO issuer. Without it the tenant names an address only
  # the server can reach (169.254.169.254, loopback, a private subnet) and gets
  # the result back from inside the perimeter.
  #
  #   uri, address = OpenLoam::OutboundUrl.resolve!(endpoint.url)
  #   http = Net::HTTP.new(uri.host, uri.port)
  #   http.ipaddr = address   # connect to the address that was CHECKED
  #
  # The pin is the load-bearing half: a host that resolves publicly during the
  # check and privately a moment later (DNS rebinding) beats a name-only check.
  module OutboundUrl
    class BlockedError < OpenLoam::Error; end

    SCHEMES = %w[http https].freeze

    # Loopback, link-local (incl. the 169.254.169.254 cloud metadata service),
    # RFC1918, carrier-grade NAT, and the IPv6 equivalents.
    BLOCKED = [
      "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16",
      "172.16.0.0/12", "192.0.0.0/24", "192.168.0.0/16", "198.18.0.0/15",
      "224.0.0.0/4", "240.0.0.0/4",
      "::1/128", "::/128", "fc00::/7", "fe80::/10", "ff00::/8",
      "64:ff9b::/96" # NAT64 reaches IPv4 space through a gateway
    ].map { |range| IPAddr.new(range) }.freeze

    module_function

    # Shape only — no DNS. Model validations call this: saving must not depend on
    # the network, and a save-time lookup proves nothing resolve! doesn't re-prove.
    def validate!(url, require_https: false, ports: nil)
      uri = parse!(url, require_https: require_https, ports: ports)
      if literal_address(uri.host) && blocked?(uri.host)
        raise BlockedError, "#{uri.host} is not a public address"
      end

      uri
    end

    # Shape, DNS, and the address to connect to — call this at FETCH time.
    def resolve!(url, require_https: false, ports: nil)
      uri = validate!(url, require_https: require_https, ports: ports)
      [ uri, address_for!(uri.host) ]
    end

    def parse!(url, require_https: false, ports: nil)
      uri = begin
        URI.parse(url.to_s)
      rescue URI::InvalidURIError => error
        raise BlockedError, "not a valid URL: #{error.message}"
      end

      raise BlockedError, "#{uri.scheme.inspect} is not an allowed scheme" unless SCHEMES.include?(uri.scheme)
      raise BlockedError, "https is required" if require_https && uri.scheme != "https"
      raise BlockedError, "no host in #{url.inspect}" if uri.host.blank?
      # Credentials in the URL are a redirect/parsing-confusion trick more often
      # than a real need, and nothing here has a use for them.
      raise BlockedError, "credentials in the URL are not allowed" if uri.userinfo.present?
      raise BlockedError, "port #{uri.port} is not allowed" if ports && !Array(ports).include?(uri.port)

      uri
    end

    # Every address the host resolves to must be allowed — a name with one
    # public and one private A record is still an internal reach.
    def address_for!(host)
      addresses = resolve_all(host)
      raise BlockedError, "#{host} does not resolve" if addresses.empty?

      addresses.each do |address|
        raise BlockedError, "#{host} resolves to the non-public address #{address}" if blocked?(address)
      end
      addresses.first
    end

    def resolve_all(host)
      return [ host ] if literal_address(host)

      Resolv.getaddresses(host)
    rescue Resolv::ResolvError
      []
    end

    def literal_address(host)
      IPAddr.new(host.to_s)
    rescue IPAddr::Error
      nil
    end

    def blocked?(address)
      ip = normalize(IPAddr.new(address.to_s))
      BLOCKED.any? { |range| range.family == ip.family && range.include?(ip) }
    rescue IPAddr::Error
      true # unparseable is not provably public
    end

    # ::ffff:a.b.c.d (mapped) and ::a.b.c.d (compatible) reach the IPv4 host,
    # so they are judged by the IPv4 ranges. IPAddr never matches across
    # families, which is exactly how "[::ffff:127.0.0.1]" slipped through.
    def normalize(ip)
      return ip unless ip.ipv6?

      value = ip.to_i
      high = value >> 32
      return IPAddr.new(value & 0xffff_ffff, Socket::AF_INET) if high == 0xffff || (high.zero? && value > 1)

      ip
    end
  end
end
