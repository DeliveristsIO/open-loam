module Loam
  module Encryption
    # AES-256-GCM sealing. GCM is *authenticated* encryption: the 16-byte auth
    # tag turns tampering — or decrypting with the wrong key — into a loud
    # failure on open, never silent garbage.
    #
    # Stored format, one string column:
    #
    #   "v1:" + base64( iv[12] ++ auth_tag[16] ++ ciphertext )              (no AAD)
    #   "v2:" + base64( iv[12] ++ auth_tag[16] ++ ciphertext )   sealed WITH AAD
    #
    # The version tag lets the scheme evolve without a stop-the-world migration:
    # v2 binds Additional Authenticated Data (the field's tenant+table+column) into
    # the auth tag, so a ciphertext moved to a DIFFERENT column/table/tenant fails
    # the tag on read — it can't be transplanted. Old "v1:" rows (no AAD) keep
    # decrypting, so upgrading is a lazy re-encrypt (loam:encryption:rotate writes
    # v2), never a data migration. The AAD is authenticated but NOT secret — it
    # never conceals anything, it only pins WHERE the ciphertext is allowed to live.
    module Cipher
      VERSION = "v1".freeze  # legacy, no AAD — still readable
      V2      = "v2".freeze  # current writes — AAD-bound
      IV_BYTES  = 12   # GCM's standard nonce size
      TAG_BYTES = 16   # full-length GCM tag; a shorter tag weakens authentication

      # Encrypt with a fresh random IV. Reusing an IV under one key is
      # catastrophic for GCM, so the IV is never derived or fixed — always
      # OpenSSL's CSPRNG, once per value. With an `aad:` the ciphertext is bound
      # to that context (v2); without one it stays v1 (a bare tenant-scoped blob).
      def self.seal(plaintext, key, aad: nil)
        cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
        cipher.key = key
        iv = cipher.random_iv
        version = aad ? V2 : VERSION
        cipher.auth_data = aad if aad # folded into the tag, not encrypted
        ciphertext = cipher.update(plaintext) + cipher.final
        tag = cipher.auth_tag(TAG_BYTES)
        "#{version}:" + [iv + tag + ciphertext].pack("m0")
      end

      # Decrypt, or raise Loam::Encryption::DecryptionError. The wrong tenant's
      # key, a tampered blob, a truncated tag, a v2 blob read with the WRONG (or
      # missing) AAD, or plain garbage all fail the same loud way — never a
      # partial or silently-wrong plaintext. A v1 blob carries no AAD, so the
      # passed `aad:` is ignored for it (backward compatible).
      def self.open(payload, key, aad: nil)
        version, blob = payload.to_s.split(":", 2)
        raise DecryptionError, "unrecognized ciphertext format" unless [ VERSION, V2 ].include?(version) && blob

        raw = blob.unpack1("m0")
        # Enforce the full IV+tag length BEFORE slicing: OpenSSL will verify a
        # truncated tag against a truncated blob, so a short payload must be
        # rejected here, not handed to the cipher.
        raise DecryptionError, "ciphertext too short" if raw.nil? || raw.bytesize < IV_BYTES + TAG_BYTES

        iv         = raw.byteslice(0, IV_BYTES)
        tag        = raw.byteslice(IV_BYTES, TAG_BYTES)
        ciphertext = raw.byteslice(IV_BYTES + TAG_BYTES..) || ""

        cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
        cipher.key = key
        cipher.iv = iv
        cipher.auth_tag = tag
        cipher.auth_data = aad if version == V2 && aad # v2 rows require the matching AAD
        plaintext = cipher.update(ciphertext) + cipher.final
        # Decryption yields ASCII-8BIT bytes; our columns hold UTF-8 text.
        plaintext.force_encoding(Encoding::UTF_8)
      rescue OpenSSL::Cipher::CipherError, ArgumentError, TypeError
        # $! is preserved as the DecryptionError's `cause`. The message stays
        # deliberately vague — it must not distinguish "wrong key" from
        # "corrupt data" to a caller.
        raise DecryptionError, "could not decrypt (wrong key or corrupt data)"
      end
    end
  end
end
