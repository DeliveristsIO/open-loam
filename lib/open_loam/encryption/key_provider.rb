module Loam
  module Encryption
    # The seam a real KMS plugs into. A provider turns (scope, purpose) into a
    # 32-byte data key; swap the default for a Vault/AWS-KMS-backed provider via
    # `Loam::Encryption.key_provider = MyKmsProvider.new` and NO call site
    # changes — Cipher and Encryptable only ever ask for a key.
    #
    # `scope` is a namespaced owner string: "tenant/5" for an entity field,
    # "user/12" for genuinely user-owned data (an MFA secret) that must decrypt
    # regardless of which tenant the user is currently acting in.
    class KeyProvider
      def data_key(scope:, purpose:)
        raise NotImplementedError, "#{self.class} must implement #data_key(scope:, purpose:)"
      end
    end

    # Default provider: derive a per-scope, per-purpose key from one master key
    # with HKDF-SHA256. Deterministic, so no key needs to be stored, and one
    # scope's key can NEVER equal another's because the scope is bound into the
    # HKDF `info`. Purpose separation means the encryption key and the
    # blind-index (HMAC) key derived for one scope are independent.
    class HkdfKeyProvider < KeyProvider
      # A fixed, non-secret salt. HKDF's strength comes from the master key's
      # entropy; the salt only has to be stable so derivation is reproducible.
      SALT = "loam.encryption.hkdf.v1".freeze
      KEY_BYTES = 32   # AES-256 and HMAC-SHA256 both take a 32-byte key

      def data_key(scope:, purpose:)
        raise ArgumentError, "scope is required to derive a key" if scope.nil? || scope.to_s.empty?

        OpenSSL::KDF.hkdf(
          Loam::Encryption.master_key,
          salt: SALT,
          # info binds the key to owner AND purpose. "tenant/5" here reproduces
          # the pre-scope format exactly, so existing ciphertext still decrypts.
          info: "loam/#{purpose}/#{scope}",
          length: KEY_BYTES,
          hash: "SHA256"
        )
      end
    end
  end
end
