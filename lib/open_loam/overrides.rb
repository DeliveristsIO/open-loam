module OpenLoam
  # Disable or replace an entry in one of OpenLoam's OWN keyed registries from an
  # initializer — customization without forking the gem, and without
  # monkeypatching. This is deliberately SMALL: Rails already handles structural
  # overriding (shadow a view/controller by path, prepend a module). Overrides
  # only covers the in-gem keyed registries, where path-shadowing doesn't reach:
  #
  #   OpenLoam::Overrides.disable(:widgets, "open_progress")            # drop a built-in widget
  #   OpenLoam::Overrides.replace(:widgets, "audit_recent") { |actor| { kind: "count", value: 0 } }
  #   OpenLoam::Overrides.disable(:broadcast_events, "open_loam.progress.")  # stop pushing an event over SSE
  #
  # THE VALUE-ADD over raw monkeypatching: a stale override (a typo, or an entry
  # that no longer exists) is caught at boot by `check!` and warned about, so a
  # silently-ineffective override is visible instead of a mystery.
  #
  # Registries with a keyed API — :widgets, :broadcast_events — honor disable AND
  # replace. Seams that are a single swappable object (Search.driver,
  # EventStream.broadcaster) are replaced by assigning them directly; Overrides
  # doesn't wrap those. Controllers/views/routes are NOT here — that's Rails'
  # path-shadowing job (see docs).
  module Overrides
    DISABLED = :__loam_disabled__

    class << self
      def disable(registry, key)
        store[registry.to_sym][key.to_s] = DISABLED
      end

      def replace(registry, key, &block)
        raise ArgumentError, "replace needs a block" unless block

        store[registry.to_sym][key.to_s] = block
      end

      def disabled?(registry, key)
        store[registry.to_sym][key.to_s] == DISABLED
      end

      # The replacement block for a key, or nil (also nil when disabled).
      def replacement(registry, key)
        value = store[registry.to_sym][key.to_s]
        value unless value == DISABLED || value.nil?
      end

      def entries(registry)
        store[registry.to_sym]
      end

      def all
        store
      end

      def reset!
        @store = Hash.new { |hash, key| hash[key] = {} }
      end

      # For tests: capture and restore the process-global override state so a
      # test's overrides don't leak (and the app's boot-time overrides survive).
      def snapshot
        store.each_with_object({}) { |(registry, keys), out| out[registry] = keys.dup }
      end

      def restore(snapshot)
        reset!
        snapshot.each { |registry, keys| store[registry].merge!(keys) }
      end

      # Overrides whose key isn't present in the live registry — a typo or a
      # removed entry. Only registries we can introspect are checked; others are
      # skipped (returned as safe). Returns [[registry, key], ...].
      def stale
        store.flat_map do |registry, keys|
          known = known_keys(registry)
          next [] if known.nil?

          keys.keys.reject { |key| known.include?(key) }.map { |key| [ registry, key ] }
        end
      end

      # Warn (once, at boot) about every stale override, and return them.
      def check!
        found = stale
        found.each do |registry, key|
          message = "[open_loam] stale override: #{registry} has no entry #{key.inspect} to disable/replace — the override is doing nothing."
          logger ? logger.warn(message) : warn(message)
        end
        found
      end

      private

      def store
        @store ||= Hash.new { |hash, key| hash[key] = {} }
      end

      # The live keys of an introspectable registry, or nil when we can't tell.
      def known_keys(registry)
        case registry.to_sym
        when :widgets then OpenLoam::Widgets.keys
        when :broadcast_events then OpenLoam.broadcast_events
        when :scheduler then defined?(OpenLoam::Scheduler) ? OpenLoam::Scheduler.registered.map { |d| d[:key] } : nil
        end
      end

      def logger
        Rails.logger if defined?(Rails) && Rails.respond_to?(:logger)
      end
    end
  end
end
