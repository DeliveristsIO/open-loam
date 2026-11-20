require "test_helper"

class OpenLoamOutboundUrlMappedTest < ActiveSupport::TestCase
  def blocked(url, **options)
    assert_raises(OpenLoam::OutboundUrl::BlockedError) { OpenLoam::OutboundUrl.validate!(url, **options) }
  end

  test "IPv4-mapped and IPv4-compatible IPv6 literals are checked as IPv4" do
    %w[
      http://[::ffff:127.0.0.1]/
      http://[::ffff:169.254.169.254]/latest/meta-data/
      http://[::ffff:10.0.0.1]/
      http://[::ffff:7f00:1]/
      http://[::127.0.0.1]/
    ].each { |url| blocked(url) }
  end

  test "NAT64 addresses are refused" do
    blocked("http://[64:ff9b::a9fe:a9fe]/")
  end

  test "a mapped public address is still allowed" do
    assert OpenLoam::OutboundUrl.validate!("http://[::ffff:93.184.216.34]/")
  end

  test "resolve! refuses a hostname that resolves to a mapped loopback address" do
    original = Resolv.method(:getaddresses)
    Resolv.define_singleton_method(:getaddresses) { |_host| [ "::ffff:127.0.0.1" ] }
    begin
      assert_raises(OpenLoam::OutboundUrl::BlockedError) { OpenLoam::OutboundUrl.resolve!("https://rebind.example/") }
    ensure
      Resolv.define_singleton_method(:getaddresses, original)
    end
  end

  test "ports: restricts the port when given and is ignored when nil" do
    error = blocked("https://example.com:8443/hook", ports: [ 443 ])
    assert_match(/port 8443/, error.message)
    assert OpenLoam::OutboundUrl.validate!("https://example.com/hook", ports: [ 443 ])
    assert OpenLoam::OutboundUrl.validate!("https://example.com:8443/hook")
  end
end
