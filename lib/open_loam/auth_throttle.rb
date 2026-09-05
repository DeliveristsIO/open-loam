module OpenLoam
  # Rate-limiting + lockout for authentication, to blunt online brute-force of
  # passwords and (especially) 6-digit TOTP codes. A DB-backed counter keyed by
  # the submitted identifier: after N failures within a window, the identifier is
  # locked; a success clears the counter.
  #
  #   OpenLoam::AuthThrottle.locked?(email)                      # refuse if true
  #   OpenLoam::AuthThrottle.record_failure(email, kind: "password", ip: request.ip)
  #   OpenLoam::AuthThrottle.clear(email, kind: "password")      # on success
  #
  # PER-IDENTIFIER is the primary defense (an attacker targets one account /
  # code). A per-ip throttle to blunt spraying across accounts is a clean
  # addition behind the same store (record_failure takes an ip) but not wired by
  # default — noted as a roadmap knob. Rack::Attack is the PRODUCTION tool
  # (needs a cache store + a gem); this DB counter is the portable,
  # single-process-correct prototype.
  #
  # Thresholds come from OpenLoam::Configs (per-tenant-overridable, but read globally
  # here at the auth layer with sane defaults):
  #   security.max_auth_attempts   (default 10)
  #   security.auth_window_minutes (default 15) — failures counted in this window
  #   security.auth_lockout_minutes(default 15) — how long "try again in N" reports
  module AuthThrottle
    module_function

    def max_attempts
      OpenLoam::Configs.get("security.max_auth_attempts", default: 10).to_i
    end

    def window
      OpenLoam::Configs.get("security.auth_window_minutes", default: 15).to_i.minutes
    end

    def lockout
      OpenLoam::Configs.get("security.auth_lockout_minutes", default: 15).to_i.minutes
    end

    # Log a failed attempt. Recorded for ANY submitted identifier — existing or
    # not — so a lockout can never become an account-existence oracle.
    def record_failure(identifier, kind:, ip: nil)
      identifier = normalize(identifier)
      return if identifier.blank?

      OpenLoam::AuthAttempt.create!(identifier: identifier, kind: kind.to_s, ip: ip)
    end

    # Locked if there are >= max failures within the window. Old attempts age out
    # of the window automatically (the window query IS the expiry — no reaper).
    #
    # Both auth call sites ask WITHOUT a kind, so failures on either factor lock
    # both. That is the deliberate choice: `clear` is kind-scoped so one factor's
    # success cannot reset the other's counter, and reading unscoped means an
    # attacker grinding TOTP also loses the password form. The cost is a wider
    # lockout on the same per-identifier DoS surface the throttle already has.
    def locked?(identifier, kind: nil)
      recent_failures(identifier, kind: kind) >= max_attempts
    end

    def recent_failures(identifier, kind: nil)
      scope = attempts(identifier).where("created_at > ?", window.ago)
      scope = scope.where(kind: kind.to_s) if kind
      scope.count
    end

    # Reset the counter — call on a SUCCESSFUL auth so a legitimate user who
    # eventually gets in isn't left throttled.
    #
    # `kind:` is mandatory in practice: clearing every kind on one factor's
    # success lets an attacker who holds the password reset the TOTP counter at
    # will, giving unlimited 6-digit guesses. Each factor clears only its own.
    def clear(identifier, kind: nil)
      scope = attempts(identifier)
      scope = scope.where(kind: Array(kind).map(&:to_s)) if kind
      scope.delete_all
    end

    # Seconds until the identifier unlocks (for the "try again in N" message),
    # or 0 when not locked.
    def remaining_lockout(identifier)
      last = attempts(identifier).maximum(:created_at)
      return 0 unless last

      seconds = (last + [ window, lockout ].max - Time.current).to_i
      seconds.positive? ? seconds : 0
    end

    def attempts(identifier)
      OpenLoam::AuthAttempt.where(identifier: normalize(identifier))
    end

    def normalize(identifier)
      identifier.to_s.strip.downcase
    end
  end
end
