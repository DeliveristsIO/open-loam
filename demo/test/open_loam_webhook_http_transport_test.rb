# demo/test/open_loam_webhook_http_transport_test.rb
require "test_helper"
require "socket"

# The real socket path, against a local TCPServer. OutboundUrl would (rightly)
# refuse 127.0.0.1, so resolve! is swapped for one that pins the test server;
# production resolution is untouched outside these tests.
class OpenLoamWebhookHttpTransportTest < ActiveSupport::TestCase
  setup do
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @requests = Queue.new
    @original_resolve = OpenLoam::OutboundUrl.singleton_class.instance_method(:resolve!)
    OpenLoam::OutboundUrl.singleton_class.send(:define_method, :resolve!) { |url, **| [ URI(url), "127.0.0.1" ] }
  end

  teardown do
    OpenLoam::OutboundUrl.singleton_class.send(:define_method, :resolve!, @original_resolve)
    @server.close unless @server.closed?
    @thread&.kill&.join(1)
    OpenLoam::Webhooks.reset_configuration!
  end

  # Accepts connections; for each, records the raw request head and lets the
  # block answer on the socket.
  def serve(&handler)
    @thread = Thread.new do
      loop do
        client = @server.accept
        head = +""
        while (line = client.gets)
          head << line
          break if line == "\r\n"
        end
        length = head[/^content-length:\s*(\d+)/i, 1].to_i
        client.read(length) if length.positive?
        @requests << head
        begin
          handler.call(client)
        rescue IOError, SystemCallError
          nil
        ensure
          client.close unless client.closed?
        end
      end
    rescue IOError, SystemCallError
      nil
    end
  end

  def post(timeout: 5)
    OpenLoam::Webhooks::HttpTransport.post("http://hooks.example.test:#{@port}/in", body: '{"a":1}',
                                           headers: { "Content-Type" => "application/json" }, timeout: timeout)
  end

  def respond(client, status, body = "", headers = {})
    head = [ "HTTP/1.1 #{status}", "Content-Length: #{body.bytesize}", "Connection: close" ]
    headers.each { |name, value| head << "#{name}: #{value}" }
    client.write("#{head.join("\r\n")}\r\n\r\n")
    client.write(body)
  end

  test "a 200 is returned with an excerpt capped, valid UTF-8 and free of NUL, even when the cut splits a character" do
    # 511 ASCII bytes then a 2-byte char straddles the 512-byte cut; a NUL and
    # a stray Latin-1 byte sit inside the excerpt.
    body = ("a" * 100).b + "\x00".b + "\xE9".b + ("b" * 409).b + ("ą" * 400).b
    serve { |client| respond(client, "200 OK", body) }

    response = post
    assert_equal 200, response.code
    assert response.excerpt.valid_encoding?
    assert_equal Encoding::UTF_8, response.excerpt.encoding
    refute_includes response.excerpt, "\u0000"
    assert_operator response.excerpt.bytesize, :<=, 512
    assert response.excerpt.start_with?("a" * 100)
  end

  test "Retry-After is surfaced and Accept-Encoding asks for identity" do
    serve { |client| respond(client, "503 Service Unavailable", "busy", "Retry-After" => "120") }

    response = post
    assert_equal 503, response.code
    assert_equal "120", response.headers["retry-after"]
    assert_match(/^accept-encoding:\s*identity\r$/i, @requests.pop)
  end

  test "a redirect is the answer, not something to follow" do
    serve { |client| respond(client, "302 Found", "", "Location" => "http://127.0.0.1:#{@port}/elsewhere") }

    response = post
    assert_equal 302, response.code
    sleep 0.1
    assert_equal 1, @requests.size
  end

  test "a receiver trickling bytes cannot hold the request past the overall deadline" do
    OpenLoam::Webhooks.timeout = 1
    serve do |client|
      client.write("HTTP/1.1 200 OK\r\nContent-Length: 100000\r\n\r\n")
      100.times do
        client.write("x")
        client.flush
        sleep 0.5
      end
    end

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raises(Timeout::Error) { post(timeout: 1) }
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 6
  end
end
