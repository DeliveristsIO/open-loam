module OpenLoam
  # RFC 4648 Base32 — the encoding authenticator apps expect for a TOTP secret.
  # Ruby ships Base64 but not Base32, and this is ~15 lines, so no dependency.
  # No padding on encode (authenticators don't want it); decode ignores case,
  # spaces and `=` padding so a secret pasted from anywhere still works.
  module Base32
    ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".freeze

    def self.encode(bytes)
      bits = bytes.bytes.map { |byte| byte.to_s(2).rjust(8, "0") }.join
      # Pad the bit string up to a multiple of 5, then map each 5 bits to a char.
      bits += "0" * ((5 - bits.length % 5) % 5)
      bits.scan(/.{5}/).map { |chunk| ALPHABET[chunk.to_i(2)] }.join
    end

    def self.decode(string)
      clean = string.to_s.upcase.gsub(/[^A-Z2-7]/, "")
      bits = clean.each_char.map { |char| ALPHABET.index(char).to_s(2).rjust(5, "0") }.join
      # Only whole bytes are data; the trailing <8 bits are encoding padding.
      bits.scan(/.{8}/).map { |byte| byte.to_i(2).chr }.join.b
    end
  end
end
