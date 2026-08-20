require "openssl"
require "loam/encryption/key_provider"
require "loam/encryption/cipher"

module Loam
  # Field-level encryption at rest, keyed per tenant.
  #
  # The facade the rest of Loam calls: `encrypt`/`decrypt` seal and open a value
  # with the tenant's derived AES-256-GCM key, and `blind_index` computes the
  # per-tenant HMAC used to find an encrypted field by exact value. Key
  # derivation is delegated to a pluggable `key_provider` (HKDF by default, a
  # KMS in production), so this module holds the scheme, not the key material.
  module Encryption
    class Error < Loam::Error; end

    # Raised when a crypto operation is attempted with no master key configured.
    class MissingMasterKeyError < Error
      def initialize(msg = "Loam::Encryption has no master key. Set LOAM_MASTER_KEY (or " \
                           "`Loam::Encryption.master_key = ...`) to a high-entropy secret, e.g. " \
                           "`SecureRandom.hex(32)`. NEVER commit it; use ENV or Rails credentials.")
        super
      end
    end

    # Raised by decrypt on the wrong key, tampering, truncation, or garbage —
    # one loud, undifferentiated failure.
    class DecryptionError < Error; end

    # HKDF extracts entropy from whatever it is given, but a short master key is
    # a short master key — refuse anything below 256 bits of material.
    MASTER_KEY_MIN_BYTES = 32

    class << self
      attr_writer :key_provider

      def key_provider
        @key_provider ||= HkdfKeyProvider.new
      end

      def master_key=(value)
        @master_key = value
      end

      def master_key
        key = @master_key || ENV["LOAM_MASTER_KEY"]
        raise MissingMasterKeyError if key.nil? || key.empty?
        if key.bytesize < MASTER_KEY_MIN_BYTES
          raise MissingMasterKeyError,
                "LOAM_MASTER_KEY is too short (#{key.bytesize} bytes); use at least " \
                "#{MASTER_KEY_MIN_BYTES}, e.g. `SecureRandom.hex(32)`."
        end
        key
      end

      # nil stays nil (an unset field is not "the empty string encrypted"); any
      # other value is stringified and sealed with the tenant's key.
      def encrypt(plaintext, tenant_id)
        return nil if plaintext.nil?
        Cipher.seal(plaintext.to_s, data_key(tenant_id, :encryption))
      end

      def decrypt(payload, tenant_id)
        return nil if payload.nil?
        Cipher.open(payload, data_key(tenant_id, :encryption))
      end

      # A deterministic, per-tenant keyed hash for exact-match lookup of an
      # encrypted field. It leaks equality WITHIN a tenant (same value → same
      # hash) — the accepted trade-off for searchability — but the per-tenant
      # HMAC key means the same value hashes differently across tenants, so
      # equality never leaks between them. Only searchable fields get one.
      def blind_index(value, tenant_id)
        return nil if value.nil?
        OpenSSL::HMAC.hexdigest("SHA256", data_key(tenant_id, :blind_index), value.to_s)
      end

      private

      def data_key(tenant_id, purpose)
        key_provider.data_key(tenant_id, purpose: purpose)
      end
    end
  end
end
