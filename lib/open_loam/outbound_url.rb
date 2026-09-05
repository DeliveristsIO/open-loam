require "ipaddr"
require "resolv"
require "uri"

module OpenLoam
  # Guard for URLs a TENANT supplies and the SERVER then fetches — webhook
  # endpoints and the SSO issuer. Without it those are a server-side request
  # forgery primitive: the tenant names an address only the server can reach
  # (169.254.169.254, 127.0.0.1, a private subnet) and reads the result, or acts
  # on it, from inside the network perimeter.
  #
  # In-gem and dependency-free by design (ADR 0002).
  #
  #   uri, address = OpenLoam::OutboundUrl.resolve!(endpoint.url)
  #   http = Net::HTTP.new(uri.host, uri.port)
  #   http.ipaddr = address   # connect to the address that was CHECKED
  #
  # Pinning the connection to the checked address is the load-bearing half. A
  # host that resolves to a public IP during validation and a private one a
  # moment later (DNS rebinding) defeats any check that only inspects the name.
  module OutboundUrl
    class BlockedError < OpenLoam::Error; end

    SCHEMES = %w[http https].freeze

    # Loopback, link-local (incl. the 169.254.169.254 cloud metadata service),
    # RFC1918, carrier-grade NAT, and the IPv6 equivalents.
    BLOCKED = [
      "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16",
      "172.16.0.0/12", "192.0.0.0/24", "192.168.0.0/16", "198.18.0.0/15",
      "224.0.0.0/4", "240.0.0.0/4",
      "::1/128", "::/128", "fc00::/7", "fe80::/10", "ff00::/8"
    ].map { |range| IPAddr.new(range) }.freeze

    module_function

    # Shape only — no DNS. This is what a model validation calls: saving must not
    # depend on the network (a DNS blip would make every endpoint unsaveable),
    # and a name that resolves publicly today can resolve privately tomorrow, so
    # a save-time lookup proves nothing that resolve! does not re-prove.
    def validate!(url, require_https: false)
      uri = parse!(url, require_https: require_https)
      if literal_address(uri.host) && blocked?(uri.host)
        raise BlockedError, "#{uri.host} is not a public address"
      end

      uri
    end

    # Shape, DNS, and the address to connect to — call this at FETCH time.
    def resolve!(url, require_https: false)
      uri = validate!(url, require_https: require_https)
      [ uri, address_for!(uri.host) ]
    end

    def parse!(url, require_https: false)
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
      ip = IPAddr.new(address.to_s)
      BLOCKED.any? { |range| range.include?(ip) }
    rescue IPAddr::Error
      true # unparseable is not provably public
    end
  end
end
