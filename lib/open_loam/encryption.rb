require "openssl"
require "open_loam/encryption/key_provider"
require "open_loam/encryption/cipher"

module OpenLoam
  # Field-level encryption at rest, keyed per tenant.
  #
  # The facade the rest of OpenLoam calls: `encrypt`/`decrypt` seal and open a value
  # with the tenant's derived AES-256-GCM key, and `blind_index` computes the
  # per-tenant HMAC used to find an encrypted field by exact value. Key
  # derivation is delegated to a pluggable `key_provider` (HKDF by default, a
  # KMS in production), so this module holds the scheme, not the key material.
  module Encryption
    class Error < OpenLoam::Error; end

    # Raised when a crypto operation is attempted with no master key configured.
    class MissingMasterKeyError < Error
      def initialize(msg = "OpenLoam::Encryption has no master key. Set OPEN_LOAM_MASTER_KEY (or " \
                           "`OpenLoam::Encryption.master_key = ...`) to a high-entropy secret, e.g. " \
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

      attr_writer :previous_master_key

      # The key being rotated AWAY from. Set it alongside the new master and
      # decryption falls back to it, which is what makes rotation possible at
      # all: open_loam:encryption:rotate has to READ every row under the old key
      # before it can rewrite it under the new one. Unset it once the rotation
      # has run everywhere.
      def previous_master_key
        key = defined?(@previous_master_key) ? @previous_master_key : nil
        key ||= ENV["OPEN_LOAM_PREVIOUS_MASTER_KEY"]
        key.presence
      end

      def master_key
        key = @master_key || ENV["OPEN_LOAM_MASTER_KEY"]
        raise MissingMasterKeyError if key.nil? || key.empty?
        if key.bytesize < MASTER_KEY_MIN_BYTES
          raise MissingMasterKeyError,
                "OPEN_LOAM_MASTER_KEY is too short (#{key.bytesize} bytes); use at least " \
                "#{MASTER_KEY_MIN_BYTES}, e.g. `SecureRandom.hex(32)`."
        end
        key
      end

      # Tenant-scoped operations — the default for entity fields via
      # OpenLoam::Encryptable. nil stays nil (an unset field is not "the empty
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
      def blind_index(value, tenant_id, table: nil, column: nil)
        blind_index_scoped(value, tenant_scope(tenant_id), table: table, column: column)
      end

      # Explicit-scope variants, for data owned by something OTHER than a tenant
      # — an MFA secret, say, keyed "user/42" so it decrypts in whatever tenant
      # the user is currently in, or at login when no tenant is chosen yet.
      def encrypt_scoped(plaintext, scope, aad: nil)
        return nil if plaintext.nil?
        Cipher.seal(plaintext.to_s, data_key(scope, :encryption), aad: aad)
      end

      def decrypt_scoped(payload, scope, aad: nil)
        return nil if payload.nil?

        Cipher.open(payload, data_key(scope, :encryption), aad: aad)
      rescue DecryptionError
        # GCM's auth tag makes "wrong key" a loud, unambiguous failure, so
        # falling back is safe: a blob that opens under the previous key really
        # was sealed with it. Writes always use the CURRENT key, so a row is
        # rotated the moment anything saves it.
        previous = previous_data_key(scope, :encryption)
        raise if previous.nil?

        Cipher.open(payload, previous, aad: aad)
      end

      # The Additional Authenticated Data that BINDS a ciphertext to where it
      # lives — the key scope (tenant/owner) + table + column. Reconstructed
      # identically on read and write, so a blob moved to a different column,
      # table, or tenant fails the auth tag. NOT the record id (see
      # OpenLoam::Encryptable): the id is unknown at INSERT time, and binding it would
      # force an ugly post-insert double-write; record-swap within one
      # tenant+table+column stays a documented residual.
      def aad(scope, table, column)
        "loam-aad:v2:#{scope}:#{table}:#{column}"
      end

      # The key is bound to (scope, table, column) for the same reason the
      # ciphertext AAD is. A key scoped only to the tenant makes one value hash
      # identically in every searchable column in that tenant: a dump correlates
      # rows across tables, and anyone who can write one such field gets an
      # equality oracle against columns they cannot read.
      #
      # table/column default to nil so an unbound caller still works — the
      # per-tenant key, which is what OpenLoam::PendingActions wants for an
      # idempotency digest that is not a column at all.
      def blind_index_scoped(value, scope, table: nil, column: nil)
        return nil if value.nil?

        purpose = table && column ? "blind_index/#{table}/#{column}" : :blind_index
        OpenSSL::HMAC.hexdigest("SHA256", data_key(scope, purpose), value.to_s)
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

      # nil unless a previous master is configured AND the provider supports the
      # fallback — a KMS-backed provider manages its own key versions, so the
      # base KeyProvider answers nil and nothing changes for it.
      def previous_data_key(scope, purpose)
        return nil unless key_provider.respond_to?(:previous_data_key)

        key_provider.previous_data_key(scope: scope, purpose: purpose)
      end
    end
  end
end
