require "test_helper"

# L-924: AES-GCM ciphertext is BOUND to its (tenant, table, column) via AAD (v2
# format), so a blob can't be transplanted to another column/table/tenant. Old
# v1 blobs (no AAD) stay readable.
class OpenLoamEncryptionAadTest < ActiveSupport::TestCase
  setup do
    @warsaw = OpenLoam::Tenant.create!(name: "Branch Warsaw", slug: "warsaw-aad")
    @krakow = OpenLoam::Tenant.create!(name: "Branch Krakow", slug: "krakow-aad")
  end

  def raw(id, column)
    Customer.connection.select_value("SELECT #{column} FROM customers WHERE id = #{id}")
  end

  test "a v2-bound field round-trips (searchable email + non-searchable tax_id)" do
    with_tenant(@warsaw) do
      c = Customer.create!(name: "Acme", email: "a@x.test", tax_id: "PL-1")
      assert_equal "a@x.test", c.reload.email
      assert_equal "PL-1", c.tax_id
      assert raw(c.id, "email").start_with?("v2:")
      assert raw(c.id, "tax_id").start_with?("v2:")
      assert_equal c, Customer.find_by_email("a@x.test"), "the blind index still finds it"
    end
  end

  # THE SWAP TEST — the whole point.
  test "a ciphertext moved to a DIFFERENT column fails the auth tag (no transplant)" do
    with_tenant(@warsaw) do
      c = Customer.create!(name: "Acme", email: "secret@x.test", tax_id: "PL-1")
      email_blob = raw(c.id, "email") # bound to (tenant, customers, email)

      # Transplant the email blob into the tax_id column.
      Customer.connection.execute("UPDATE customers SET tax_id = #{Customer.connection.quote(email_blob)} WHERE id = #{c.id}")

      error = assert_raises(OpenLoam::Encryption::DecryptionError) { Customer.find(c.id).tax_id }
      assert_match(/wrong key or corrupt data/, error.message)
      # And it certainly did NOT decrypt to the email's plaintext.
      refute_equal "secret@x.test", (Customer.find(c.id).tax_id rescue nil)
    end
  end

  test "a legacy v1 ciphertext (no AAD) still decrypts — existing data isn't bricked" do
    with_tenant(@warsaw) do
      key = OpenLoam::Encryption.send(:data_key, "tenant/#{@warsaw.id}", :encryption)
      v1_blob = OpenLoam::Encryption::Cipher.seal("legacy-value", key) # no aad -> v1
      assert v1_blob.start_with?("v1:")

      c = Customer.create!(name: "Old", email: "o@x.test", tax_id: "x")
      Customer.connection.execute("UPDATE customers SET tax_id = #{Customer.connection.quote(v1_blob)} WHERE id = #{c.id}")

      assert_equal "legacy-value", Customer.find(c.id).tax_id, "a v1 blob reads back (backward compatible)"
    end
  end

  test "rotation upgrades a v1 row to v2 (AAD-bound)" do
    with_tenant(@warsaw) do
      key = OpenLoam::Encryption.send(:data_key, "tenant/#{@warsaw.id}", :encryption)
      c = Customer.create!(name: "Rot", email: "r@x.test", tax_id: "x")
      Customer.connection.execute("UPDATE customers SET tax_id = #{Customer.connection.quote(OpenLoam::Encryption::Cipher.seal('rotate-me', key))} WHERE id = #{c.id}")
      assert raw(c.id, "tax_id").start_with?("v1:")

      Customer.find(c.id).open_loam_reencrypt!

      assert raw(c.id, "tax_id").start_with?("v2:"), "rotate re-encrypts to v2"
      assert_equal "rotate-me", Customer.find(c.id).tax_id
    end
  end

  test "cross-tenant decryption still fails (unchanged from L-901)" do
    warsaw_blob = with_tenant(@warsaw) { c = Customer.create!(name: "W", email: "w@x.test", tax_id: "PL-W"); raw(c.id, "tax_id") }

    with_tenant(@krakow) do
      # Krakow's key can't open a Warsaw-sealed blob (different per-tenant key AND
      # a different AAD).
      k = Customer.create!(name: "K", email: "k@x.test", tax_id: "x")
      Customer.connection.execute("UPDATE customers SET tax_id = #{Customer.connection.quote(warsaw_blob)} WHERE id = #{k.id}")
      assert_raises(OpenLoam::Encryption::DecryptionError) { Customer.find(k.id).tax_id }
    end
  end

  test "the audit trail still redacts encrypted fields (AAD didn't regress redaction)" do
    with_tenant(@warsaw) do
      Customer.create!(name: "Acme", email: "leak@x.test", tax_id: "PL-LEAK")
      dump = OpenLoam::AuditRecord.where(auditable_type: "Customer").map { |a| a.changeset.to_json }.join
      refute_includes dump, "leak@x.test"
      refute_includes dump, "PL-LEAK"
      assert_includes dump, "[encrypted]"
    end
  end
end
