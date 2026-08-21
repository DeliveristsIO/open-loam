require "set"

module Loam
  # A small, dependency-free "next run" calculator for a standard 5-field cron
  # expression ("min hour dom month dow") plus an "interval:N" (every N seconds)
  # form — same stdlib-only spirit as Loam::Totp / Loam::Base32. Timezone-aware;
  # always returns UTC. Supports `*`, lists (`1,15`), ranges (`1-5`), and steps
  # (`*/15`, `0-30/10`), and the classic cron day-of-month / day-of-week OR quirk
  # (when BOTH are restricted, a match on either fires).
  module Cron
    RANGES = { min: 0..59, hour: 0..23, dom: 1..31, mon: 1..12, dow: 0..6 }.freeze
    MAX_HORIZON = 4 # years to search before giving up (covers Feb-29 schedules)

    module_function

    # The next run strictly after `from`, evaluated in `zone`, returned in UTC.
    def next_after(expr, from:, zone: "UTC")
      expr = expr.to_s.strip

      if expr.start_with?("interval:")
        seconds = expr.split(":", 2).last.to_i
        raise ArgumentError, "interval must be a positive number of seconds: #{expr.inspect}" unless seconds.positive?

        return (from + seconds).utc
      end

      next_cron(expr, from, zone)
    end

    def next_cron(expr, from, zone)
      fields = expr.split(/\s+/)
      raise ArgumentError, "cron must have 5 fields (min hour dom month dow): #{expr.inspect}" unless fields.size == 5

      min  = parse_field(fields[0], RANGES[:min])
      hour = parse_field(fields[1], RANGES[:hour])
      dom  = parse_field(fields[2], RANGES[:dom])
      mon  = parse_field(fields[3], RANGES[:mon])
      dow  = parse_field(fields[4], RANGES[:dow], dow: true)
      dom_restricted = fields[2] != "*"
      dow_restricted = fields[4] != "*"

      time = from.in_time_zone(zone).change(sec: 0) + 60
      limit = time + MAX_HORIZON.years

      while time < limit
        unless mon.include?(time.month) && day_matches?(time, dom, dow, dom_restricted, dow_restricted)
          time = (time + 1.day).change(hour: 0, min: 0) # skip the whole non-matching day
          next
        end
        return time.utc if hour.include?(time.hour) && min.include?(time.min)

        time += 60
      end

      raise ArgumentError, "no cron match within #{MAX_HORIZON} years for #{expr.inspect}"
    end

    def day_matches?(time, dom, dow, dom_restricted, dow_restricted)
      if dom_restricted && dow_restricted
        dom.include?(time.day) || dow.include?(time.wday) # OR quirk
      elsif dom_restricted
        dom.include?(time.day)
      elsif dow_restricted
        dow.include?(time.wday)
      else
        true
      end
    end

    # Parse one field into the set of matching integers.
    def parse_field(field, range, dow: false)
      values = Set.new

      field.to_s.split(",").each do |part|
        base, step = part.split("/", 2)
        step = step ? Integer(step) : 1
        raise ArgumentError, "bad step in #{part.inspect}" unless step.positive?

        if base == "*"
          lo, hi = range.min, range.max
        elsif base.include?("-")
          lo, hi = base.split("-", 2).map { |n| Integer(n) }
        else
          lo = hi = Integer(base)
        end

        (lo..hi).step(step) do |value|
          value = 0 if dow && value == 7 # both 0 and 7 mean Sunday
          raise ArgumentError, "value #{value} out of range for #{field.inspect}" unless range.include?(value)

          values << value
        end
      end

      values
    end
  end
end
