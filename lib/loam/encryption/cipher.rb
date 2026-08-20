module Loam
  module Encryption
    # AES-256-GCM sealing. GCM is *authenticated* encryption: the 16-byte auth
    # tag turns tampering — or decrypting with the wrong key — into a loud
    # failure on open, never silent garbage.
    #
    # Stored format, one string column:
    #
    #   "v1:" + base64( iv[12] ++ auth_tag[16] ++ ciphertext )
    #
    # The "v1" prefix is a version tag: a future scheme (a rotated key, a new
    # cipher) writes "v2:" and old "v1:" rows keep decrypting, so rotation is a
    # lazy re-encrypt, not a stop-the-world data migration (see loam:encryption).
    module Cipher
      VERSION = "v1".freeze
      IV_BYTES  = 12   # GCM's standard nonce size
      TAG_BYTES = 16   # full-length GCM tag; a shorter tag weakens authentication

      # Encrypt with a fresh random IV. Reusing an IV under one key is
      # catastrophic for GCM, so the IV is never derived or fixed — always
      # OpenSSL's CSPRNG, once per value.
      def self.seal(plaintext, key)
        cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
        cipher.key = key
        iv = cipher.random_iv
        # No AAD: per-tenant key separation already isolates tenants, so binding
        # extra associated data into the tag would buy nothing here.
        # TODO (follow-up): bind the column/record identity as AAD so a ciphertext
        # cannot be transplanted between columns/rows — a documented tradeoff, not
        # yet enforced.
        ciphertext = cipher.update(plaintext) + cipher.final
        tag = cipher.auth_tag(TAG_BYTES)
        "#{VERSION}:" + [iv + tag + ciphertext].pack("m0")
      end

      # Decrypt, or raise Loam::Encryption::DecryptionError. The wrong tenant's
      # key, a tampered blob, a truncated tag, or plain garbage all fail the
      # same loud way — never a partial or silently-wrong plaintext.
      def self.open(payload, key)
        version, blob = payload.to_s.split(":", 2)
        raise DecryptionError, "unrecognized ciphertext format" unless version == VERSION && blob

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
