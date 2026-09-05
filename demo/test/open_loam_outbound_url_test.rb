require "test_helper"

# OpenLoam::OutboundUrl — the guard on URLs a tenant supplies and the server then
# fetches (webhook endpoints, the SSO issuer). Without it those are an SSRF
# primitive: the tenant names an address only the server can reach.
class OpenLoamOutboundUrlTest < ActiveSupport::TestCase
  def blocked(url, **options)
    assert_raises(OpenLoam::OutboundUrl::BlockedError) { OpenLoam::OutboundUrl.validate!(url, **options) }
  end

  test "the cloud metadata service is refused" do
    error = blocked("http://169.254.169.254/latest/meta-data/iam/security-credentials/")
    assert_match(/not a public address/, error.message)
  end

  test "loopback and private ranges are refused" do
    %w[
      http://127.0.0.1/admin
      http://0.0.0.0/
      http://10.1.2.3/internal
      http://192.168.1.1/router
      http://172.16.0.5/
      http://100.64.0.1/
      http://[::1]/
    ].each { |url| blocked(url) }
  end

  test "a non-http scheme is refused" do
    blocked("file:///etc/passwd")
    blocked("gopher://127.0.0.1:11211/")
    blocked("ftp://internal.example/")
  end

  test "credentials in the URL are refused" do
    error = blocked("https://user:pass@example.com/hook")
    assert_match(/credentials/, error.message)
  end

  test "require_https rejects plain http" do
    assert OpenLoam::OutboundUrl.validate!("http://example.com/hook"), "allowed when https is not required"
    blocked("http://example.com/hook", require_https: true)
  end

  test "an ordinary public URL passes" do
    uri = OpenLoam::OutboundUrl.validate!("https://hooks.example.com/receive?x=1")

    assert_equal "hooks.example.com", uri.host
    assert_equal "/receive", uri.path
  end

  test "validate! does NOT hit DNS, so saving never depends on the network" do
    # A reserved TLD that cannot resolve — shape is all that is checked here.
    assert OpenLoam::OutboundUrl.validate!("https://nothing.invalid/hook")
  end

  test "resolve! rejects a name that resolves nowhere" do
    error = assert_raises(OpenLoam::OutboundUrl::BlockedError) do
      OpenLoam::OutboundUrl.resolve!("https://nothing.invalid/hook")
    end
    assert_match(/does not resolve/, error.message)
  end

  test "resolve! returns the address the caller must connect to" do
    # Pinning the connection to the address that was CHECKED is what closes the
    # DNS-rebinding window between the check and the connect.
    _uri, address = OpenLoam::OutboundUrl.resolve!("https://93.184.216.34/hook")

    assert_equal "93.184.216.34", address
  end
end

# The two models that accept a tenant-supplied URL must refuse an internal one
# at save, so the error lands on the form rather than in a job log.
class OpenLoamOutboundUrlModelTest < ActiveSupport::TestCase
  setup { @tenant = OpenLoam::Tenant.create!(name: "T", slug: "outbound-url") }

  test "a webhook endpoint cannot point at the metadata service" do
    endpoint = with_tenant(@tenant) do
      OpenLoam::WebhookEndpoint.new(url: "http://169.254.169.254/latest/meta-data/", event_pattern: "rental.")
    end

    assert_not endpoint.valid?
    assert endpoint.errors[:url].any?
  end

  test "an SSO issuer must be external and https" do
    internal = with_tenant(@tenant) do
      OpenLoam::SsoProvider.new(name: "X", protocol: "oidc", domain: "x.example", jit_role: "employee",
                                issuer: "http://127.0.0.1:8080/realms/master")
    end
    assert_not internal.valid?
    assert internal.errors[:issuer].any?

    plain = with_tenant(@tenant) do
      OpenLoam::SsoProvider.new(name: "X", protocol: "oidc", domain: "x.example", jit_role: "employee",
                                issuer: "http://idp.example.com")
    end
    assert_not plain.valid?, "the client_secret travels over this, so https is mandatory"
  end
end
