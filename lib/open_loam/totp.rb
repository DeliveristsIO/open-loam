require "openssl"
require "securerandom"
require "uri"
require "erb"

module OpenLoam
  # RFC 6238 time-based one-time passwords — the shipped second factor.
  # HMAC-SHA1, 30-second step, 6 digits, ±1 step of drift tolerance (so a code
  # entered a few seconds either side of a boundary still verifies). Hand-rolled
  # on OpenSSL rather than pulling a gem; it is ~20 lines of a well-specified
  # algorithm, verified against the RFC's own test vectors in the test suite.
  module Totp
    DIGITS = 6
    PERIOD = 30      # seconds per step
    DRIFT  = 1       # accept the neighbouring step on each side

    # A fresh random secret, base32-encoded for authenticator apps. 20 bytes
    # (160 bits) is the RFC-recommended size for SHA1.
    def self.generate_secret(bytes: 20)
      OpenLoam::Base32.encode(SecureRandom.random_bytes(bytes))
    end

    # True if `code` is valid for `secret` right now.
    def self.verify(secret, code, at: Time.now.to_i)
      !matching_step(secret, code, at: at).nil?
    end

    # The step counter a code matches (within the drift window), or nil. Callers
    # that must prevent replay (login, sudo) persist this and reject a code whose
    # step is not strictly greater than the last accepted one. The length/charset
    # check runs FIRST, so a malformed code never reaches the constant-time
    # compare (which assumes equal-length inputs).
    def self.matching_step(secret, code, at: Time.now.to_i)
      code = code.to_s.gsub(/\s+/, "")
      return nil unless code.match?(/\A\d{#{DIGITS}}\z/)

      counter = at.to_i / PERIOD
      (-DRIFT..DRIFT).each do |offset|
        step = counter + offset
        return step if ActiveSupport::SecurityUtils.secure_compare(code_at(secret, step), code)
      end
      nil
    end

    # The HOTP code for a given step counter (RFC 4226 dynamic truncation).
    def self.code_at(secret, counter, digits: DIGITS)
      hmac = OpenSSL::HMAC.digest("SHA1", OpenLoam::Base32.decode(secret), [counter].pack("Q>"))
      offset = hmac.bytes.last & 0x0f
      truncated = hmac[offset, 4].unpack1("N") & 0x7fffffff
      (truncated % (10**digits)).to_s.rjust(digits, "0")
    end

    # The otpauth:// URI an authenticator app imports (usually via QR — rendering
    # the QR image is a UI nicety left for later; the URI + secret are enough).
    def self.provisioning_uri(secret, account:, issuer:)
      label = ERB::Util.url_encode("#{issuer}:#{account}")
      query = URI.encode_www_form(
        secret: secret, issuer: issuer, algorithm: "SHA1", digits: DIGITS, period: PERIOD
      )
      "otpauth://totp/#{label}?#{query}"
    end
  end
end
