require "test_helper"

# Loam::Encryptable on a real entity: Customer.email (encrypted + searchable)
# and Customer.tax_id (encrypted, not searchable). These are security tests —
# they assert what a DB dump leaks, that one tenant's key never opens another's
# data, and that the plaintext never reaches the audit trail.
class LoamEncryptionTest < ActiveSupport::TestCase
  setup do
    @warsaw = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-enc")
    @krakow = Loam::Tenant.create!(name: "Branch Krakow", slug: "krakow-enc")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    with_tenant(@warsaw) { Loam::Membership.create!(user: @anna, role: "manager") }
  end

  test "an encrypted field round-trips: plaintext in, plaintext out" do
    with_tenant(@warsaw) do
      c = Customer.create!(name: "Acme", email: "ceo@acme.test", tax_id: "PL-999")
      c.reload
      assert_equal "ceo@acme.test", c.email
      assert_equal "PL-999", c.tax_id
    end
  end

  test "the raw database column holds versioned ciphertext, never the plaintext" do
    id = with_tenant(@warsaw) { Customer.create!(name: "Acme", email: "ceo@acme.test", tax_id: "PL-999").id }

    # Read the columns the way a DB dump would — straight SQL, no model.
    raw_email = Customer.connection.select_value("SELECT email FROM customers WHERE id = #{id}")
    raw_tax   = Customer.connection.select_value("SELECT tax_id FROM customers WHERE id = #{id}")

    assert raw_email.start_with?("v1:"), "ciphertext must carry the version tag"
    assert raw_tax.start_with?("v1:")
    refute_includes raw_email, "ceo@acme.test", "a dump must not leak the plaintext"
    refute_includes raw_tax, "PL-999"
  end

  test "encrypting or reading with no tenant context raises MissingTenantError" do
    record = with_tenant(@warsaw) { Customer.create!(name: "Acme", email: "ceo@acme.test", tax_id: "PL-999") }

    fresh = with_tenant(@warsaw) { Customer.new }

    Loam::Current.reset
    assert_raises(Loam::MissingTenantError) { record.email }     # read needs the tenant's key
    assert_raises(Loam::MissingTenantError) { fresh.email = "x" } # and so does write
  end

  test "one tenant's ciphertext cannot be decrypted in another tenant's context" do
    id = with_tenant(@warsaw) { Customer.create!(name: "Acme", email: "ceo@acme.test", tax_id: "PL-999").id }

    # Krakow cannot even see the row (tenant scope)...
    with_tenant(@krakow) do
      assert_equal 0, Customer.count
      assert_nil Customer.find_by(id: id)
    end

    # ...and forcing the row across the tenant boundary fails the GCM auth tag,
    # rather than quietly decrypting Warsaw's data under Krakow's key.
    with_tenant(@krakow) do
      leaked = Customer.unscoped.find(id)
      assert_raises(Loam::Encryption::DecryptionError) { leaked.email }
    end
  end

  test "a searchable encrypted field is found by exact match, tenant-scoped" do
    with_tenant(@warsaw) { Customer.create!(name: "Acme", email: "shared@acme.test", tax_id: "PL-1") }
    with_tenant(@krakow) { Customer.create!(name: "Acme KR", email: "shared@acme.test", tax_id: "KR-1") }

    with_tenant(@warsaw) do
      found = Customer.find_by_email("shared@acme.test")
      assert found, "exact-match lookup via the blind index must find it"
      assert_equal "shared@acme.test", found.email
    end

    # Same address, but Krakow's blind-index key differs, so Warsaw's row is not
    # findable from Krakow — equality never leaks across tenants.
    with_tenant(@krakow) do
      assert_equal 1, Customer.where_email("shared@acme.test").count, "only Krakow's own row"
      assert_equal "KR-1", Customer.find_by_email("shared@acme.test").tax_id
    end
  end

  test "the blind index of the same value differs across tenants" do
    w = Loam::Encryption.blind_index("same@x.test", @warsaw.id)
    k = Loam::Encryption.blind_index("same@x.test", @krakow.id)
    refute_equal w, k
    assert_equal w, Loam::Encryption.blind_index("same@x.test", @warsaw.id), "stable within a tenant"
  end

  # Regression: a nil tenant makes the scope "tenant/", a nil owner makes
  # "user/" — a degenerate scope that must be refused, not keyed to a real key
  # shared across every such record.
  test "a nil tenant or degenerate scope refuses to derive a key" do
    assert_raises(ArgumentError) { Loam::Encryption.encrypt("x", nil) }
    assert_raises(ArgumentError) { Loam::Encryption.decrypt("v1:whatever", nil) }
    assert_raises(ArgumentError) { Loam::Encryption.blind_index("x", nil) }
    assert_raises(ArgumentError) { Loam::Encryption.encrypt_scoped("x", "user/") }
  end

  test "the audit trail records the fact of change, never the plaintext or ciphertext" do
    with_tenant(@warsaw, actor: @anna) do
      c = Customer.create!(name: "Acme", email: "old@acme.test", tax_id: "PL-1")
      c.update!(email: "new@acme.test")

      audits = Loam::AuditRecord.where(auditable_type: "Customer", auditable_id: c.id)
      dump = audits.map { |a| a.changeset.to_json }.join

      refute_includes dump, "old@acme.test", "no plaintext in the audit trail"
      refute_includes dump, "new@acme.test"
      refute_includes dump, "v1:", "no ciphertext either"
      refute_includes dump, "email_hash", "and never the blind index"

      create_audit = audits.find_by(action: "create")
      assert_equal "[encrypted]", create_audit.changeset["email"]
      assert_equal "[encrypted]", create_audit.changeset["tax_id"]
      assert_equal [ nil, "Acme" ], create_audit.changeset["name"], "non-encrypted fields keep their full [old, new] change"
    end
  end

  test "declaring a field both searchable_by and encrypts raises at class load" do
    # Plain classes, NOT Loam::TenantRecord subclasses: an anonymous AR subclass
    # would linger in TenantRecord.descendants and leak into the global search.
    # The conflict is caught at DSL time, before any database access, so no real
    # model is needed to prove it — in either declaration order.
    assert_raises(Loam::Error) do
      Class.new do
        include Loam::Searchable
        include Loam::Encryptable
        searchable_by :email
        encrypts :email, searchable: true
      end
    end

    assert_raises(Loam::Error) do
      Class.new do
        include Loam::Searchable
        include Loam::Encryptable
        encrypts :email, searchable: true
        searchable_by :email
      end
    end
  end
end

# The admin flow, end to end: a manager creates a customer, the show screen
# renders the decrypted values, and the encrypted email is findable by exact match.
class AdminEncryptionFlowTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = Loam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-enc-flow")
    @anna = User.create!(name: "Anna", email: "anna@example.test", password: "password")
    with_tenant(@tenant) { Loam::Membership.create!(user: @anna, role: "manager") }
    post admin_session_path, params: { email: "anna@example.test", password: "password" }
  end

  test "create via the admin form, then the show screen decrypts and lookup finds it" do
    post admin_customers_path, params: { customer: { name: "Globex", email: "ap@globex.test", tax_id: "PL-42" } }
    assert_response :redirect

    id = with_tenant(@tenant) { Customer.find_by_email("ap@globex.test")&.id }
    assert id, "the encrypted email must be findable by its blind index after an admin create"

    get admin_customer_path(id)
    assert_response :success
    assert_match "ap@globex.test", response.body, "the show screen decrypts for display"
    assert_match "PL-42", response.body

    # The rendered HTML shows plaintext, but the stored column is ciphertext.
    raw = Customer.connection.select_value("SELECT email FROM customers WHERE id = #{id}")
    assert raw.start_with?("v1:")
  end
end
