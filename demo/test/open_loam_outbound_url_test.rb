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

# The uploaded CSV is a payload of real records — often rows headed for
# encrypted columns. It must not sit in the clear in the queue backend.
class OpenLoamImportPayloadTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = OpenLoam::Tenant.create!(name: "T", slug: "import-payload")
    @manager = User.create!(name: "M", email: "m@import.test", password: "password123")
    with_tenant(@tenant) { OpenLoam::Membership.create!(user: @manager, role: "manager") }
    post admin_session_path, params: { email: "m@import.test", password: "password123" }
  end

  test "the job carries a blob id, never the file" do
    csv = "name,email\nNowak,nowak@secret.test\n"

    assert_enqueued_with(job: ImportJob) do
      post admin_imports_path, params: {
        entity_type: "Customer", csv: csv, commit: "Import",
        mapping: { "name" => "name", "email" => "email" }
      }
    end

    arguments = ActiveJob::Base.queue_adapter.enqueued_jobs.last["arguments"].inspect

    assert_not_includes arguments, "nowak@secret.test", "no row values in the queue payload"
    assert_not_includes arguments, "name,email", "not even the header"
    assert_match(/blob_id/, arguments)
  end

  test "csv is filtered out of the request log" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    logged = filter.filter("csv" => "name,email\nNowak,nowak@secret.test", "code" => "123456", "entity_type" => "Customer")

    assert_equal "[FILTERED]", logged["csv"]
    assert_equal "[FILTERED]", logged["code"], "a live TOTP must not be logged either"
    assert_equal "Customer", logged["entity_type"], "and ordinary params still log"
  end
end

# The blind-index key used to be scoped to the tenant alone, unlike the
# ciphertext AAD, which binds table and column too.
class OpenLoamBlindIndexScopeTest < ActiveSupport::TestCase
  setup { @tenant = OpenLoam::Tenant.create!(name: "T", slug: "blind-index-scope") }

  test "the same value hashes differently per column, so a dump cannot correlate" do
    value = "nowak@example.test"

    email = OpenLoam::Encryption.blind_index(value, @tenant.id, table: "customers", column: :email)
    other = OpenLoam::Encryption.blind_index(value, @tenant.id, table: "customers", column: :billing_email)
    other_table = OpenLoam::Encryption.blind_index(value, @tenant.id, table: "leads", column: :email)

    assert_not_equal email, other, "one value must not hash alike across columns"
    assert_not_equal email, other_table, "nor across tables"
  end

  test "it still hashes differently across tenants, and consistently within one" do
    other_tenant = OpenLoam::Tenant.create!(name: "O", slug: "blind-index-other")
    args = { table: "customers", column: :email }

    mine = OpenLoam::Encryption.blind_index("x@y.test", @tenant.id, **args)
    again = OpenLoam::Encryption.blind_index("x@y.test", @tenant.id, **args)
    theirs = OpenLoam::Encryption.blind_index("x@y.test", other_tenant.id, **args)

    assert_equal mine, again, "lookup depends on it being deterministic"
    assert_not_equal mine, theirs
  end

  test "searchable lookup still finds the record it wrote" do
    with_tenant(@tenant) do
      OpenLoam::Current.actor = User.create!(name: "A", email: "a@bi.test", password: "password123")
      OpenLoam::Membership.create!(user: OpenLoam::Current.actor, role: "manager")
      customer = Customer.create!(name: "Nowak", email: "nowak@bi.test")

      assert_equal customer.id, Customer.find_by_email("nowak@bi.test")&.id
      assert_nil Customer.find_by_email("someone@else.test")
      OpenLoam::Current.actor = nil
    end
  end
end

# Rotation was documented and impossible: swapping the master made every read
# fail the auth tag before anything could rewrite it, so the rake task the
# initializer points at for a key compromise could never run.
class OpenLoamKeyRotationTest < ActiveSupport::TestCase
  setup do
    @tenant = OpenLoam::Tenant.create!(name: "T", slug: "key-rotation")
    @old_key = OpenLoam::Encryption.master_key
  end

  teardown do
    OpenLoam::Encryption.master_key = @old_key
    OpenLoam::Encryption.previous_master_key = nil
  end

  def customer_with_email(email)
    with_tenant(@tenant) do
      OpenLoam::Current.actor = User.create!(name: "A", email: "a#{SecureRandom.hex(4)}@rot.test", password: "password123")
      OpenLoam::Membership.create!(user: OpenLoam::Current.actor, role: "manager")
      record = Customer.create!(name: "Nowak", email: email)
      OpenLoam::Current.actor = nil
      record
    end
  end

  test "a row sealed under the old key still reads after the master is swapped" do
    customer = customer_with_email("nowak@rot.test")

    OpenLoam::Encryption.previous_master_key = @old_key
    OpenLoam::Encryption.master_key = SecureRandom.hex(32)

    assert_equal "nowak@rot.test", with_tenant(@tenant) { Customer.find(customer.id).email }
  end

  test "without the previous key it fails loudly rather than returning garbage" do
    customer = customer_with_email("nowak2@rot.test")

    OpenLoam::Encryption.previous_master_key = nil
    OpenLoam::Encryption.master_key = SecureRandom.hex(32)

    assert_raises(OpenLoam::Encryption::DecryptionError) do
      with_tenant(@tenant) { Customer.find(customer.id).email }
    end
  end

  test "re-encrypting rewrites the row under the new key, and the blind index with it" do
    customer = customer_with_email("nowak3@rot.test")

    OpenLoam::Encryption.previous_master_key = @old_key
    OpenLoam::Encryption.master_key = SecureRandom.hex(32)
    with_tenant(@tenant) { Customer.find(customer.id).open_loam_reencrypt! }

    # The rotation is finished, so the old key goes away entirely.
    OpenLoam::Encryption.previous_master_key = nil

    with_tenant(@tenant) do
      assert_equal "nowak3@rot.test", Customer.find(customer.id).email
      assert_equal customer.id, Customer.find_by_email("nowak3@rot.test")&.id, "the blind index was rebuilt too"
    end
  end
end
