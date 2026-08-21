module Loam
  # Read API for per-tenant managed lookup lists (Loam::Dictionary /
  # Loam::DictionaryEntry). Everything is tenant-scoped automatically and
  # memoized per request in Loam::Current.dictionary_cache (keyed with the tenant
  # id, so an as_tenant switch mid-request can't read another tenant's list) —
  # the same simple prototype cache as Loam::Configs.
  #
  #   Loam::Dictionaries.entries("damage_severity")        # active, ordered
  #   Loam::Dictionaries.default("damage_severity")        # the default entry
  #   Loam::Dictionaries.label_for("damage_severity", "critical")  # => "Critical"
  module Dictionaries
    class << self
      # The dictionary for the current tenant, or nil.
      def get(key)
        memo([:dict, key.to_s]) { Loam::Dictionary.find_by(key: key.to_s) }
      end

      # Active entries, ordered by position. Empty for an unknown key.
      def entries(key)
        dictionary = get(key)
        return [] unless dictionary

        memo([:entries, key.to_s]) { dictionary.entries.active.ordered.to_a }
      end

      # The default entry (the first flagged one), or nil.
      def default(key)
        entries(key).find(&:is_default?)
      end

      # The label for a stored value — or the raw value itself when the key or
      # value is unknown, so an old/foreign value still renders as something.
      def label_for(key, value)
        return value if value.blank?

        entry = entries(key).find { |e| e.value == value.to_s }
        entry ? entry.label : value
      end

      def clear_cache
        Loam::Current.dictionary_cache = {}
      end

      private

      def memo(subkey)
        store = (Loam::Current.dictionary_cache ||= {})
        cache_key = subkey + [ Loam.tenant&.id ]
        return store[cache_key] if store.key?(cache_key)

        store[cache_key] = yield
      end
    end
  end
end
