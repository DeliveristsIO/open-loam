module Loam
  module Encryption
    # The seam a real KMS plugs into. A provider turns (tenant, purpose) into a
    # 32-byte data key; swap the default for a Vault/AWS-KMS-backed provider via
    # `Loam::Encryption.key_provider = MyKmsProvider.new` and NO call site
    # changes — Cipher and Encryptable only ever ask for a key.
    class KeyProvider
      def data_key(tenant_id, purpose:)
        raise NotImplementedError, "#{self.class} must implement #data_key(tenant_id, purpose:)"
      end
    end

    # Default provider: derive a per-tenant, per-purpose key from one master key
    # with HKDF-SHA256. Deterministic, so no key needs to be stored, and tenant
    # A's key can NEVER equal tenant B's because the tenant id is bound into the
    # HKDF `info`. Purpose separation means the encryption key and the
    # blind-index (HMAC) key derived for one tenant are independent.
    class HkdfKeyProvider < KeyProvider
      # A fixed, non-secret salt. HKDF's strength comes from the master key's
      # entropy; the salt only has to be stable so derivation is reproducible.
      SALT = "loam.encryption.hkdf.v1".freeze
      KEY_BYTES = 32   # AES-256 and HMAC-SHA256 both take a 32-byte key

      def data_key(tenant_id, purpose:)
        raise ArgumentError, "tenant_id is required to derive a key" if tenant_id.nil?

        OpenSSL::KDF.hkdf(
          Loam::Encryption.master_key,
          salt: SALT,
          info: "loam/#{purpose}/tenant/#{tenant_id}",
          length: KEY_BYTES,
          hash: "SHA256"
        )
      end
    end
  end
end
