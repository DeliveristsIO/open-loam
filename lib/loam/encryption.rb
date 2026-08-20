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

      # Tenant-scoped operations — the default for entity fields via
      # Loam::Encryptable. nil stays nil (an unset field is not "the empty
      # string encrypted"); any other value is stringified and sealed.
      def encrypt(plaintext, tenant_id)
        encrypt_scoped(plaintext, tenant_scope(tenant_id))
      end

      def decrypt(payload, tenant_id)
        decrypt_scoped(payload, tenant_scope(tenant_id))
      end

      # A deterministic, per-tenant keyed hash for exact-match lookup of an
      # encrypted field. It leaks equality WITHIN a tenant (same value → same
      # hash) — the accepted trade-off for searchability — but the per-tenant
      # HMAC key means the same value hashes differently across tenants, so
      # equality never leaks between them. Only searchable fields get one.
      def blind_index(value, tenant_id)
        blind_index_scoped(value, tenant_scope(tenant_id))
      end

      # Explicit-scope variants, for data owned by something OTHER than a tenant
      # — an MFA secret, say, keyed "user/42" so it decrypts in whatever tenant
      # the user is currently in, or at login when no tenant is chosen yet.
      def encrypt_scoped(plaintext, scope)
        return nil if plaintext.nil?
        Cipher.seal(plaintext.to_s, data_key(scope, :encryption))
      end

      def decrypt_scoped(payload, scope)
        return nil if payload.nil?
        Cipher.open(payload, data_key(scope, :encryption))
      end

      def blind_index_scoped(value, scope)
        return nil if value.nil?
        OpenSSL::HMAC.hexdigest("SHA256", data_key(scope, :blind_index), value.to_s)
      end

      private

      # "tenant/5" reproduces the pre-scope HKDF info exactly (see HkdfKeyProvider).
      def tenant_scope(tenant_id)
        "tenant/#{tenant_id}"
      end

      # Central guard for every crypto path (tenant and explicit scope alike): a
      # nil tenant makes the scope "tenant/", a nil owner id makes "user/" — a
      # degenerate scope that would otherwise derive a real, SHARED key. Refuse
      # it here so `encrypt(x, nil)` fails like the Encryptable-layer guard does,
      # rather than silently keying unrelated records together.
      def data_key(scope, purpose)
        if scope.nil? || scope.to_s.strip.empty? || scope.to_s.end_with?("/")
          raise ArgumentError, "refusing to derive an encryption key from a degenerate scope #{scope.inspect}"
        end

        key_provider.data_key(scope: scope, purpose: purpose)
      end
    end
  end
end
