module OpenLoam
  # The one way to read and write per-tenant settings.
  #
  #   OpenLoam::Configs.get("rental.late_fee_per_day")          # resolved for the current tenant
  #   OpenLoam::Configs.set("rental.late_fee_per_day", 45)      # this tenant's override
  #   OpenLoam::Configs.set("rental.currency", "PLN", scope: :global)
  #   OpenLoam::Configs.reset("rental.late_fee_per_day")        # drop the override → fall back
  #
  # Resolution order, most specific first:
  #   1. the current tenant's OVERRIDE row (tenant_id = current tenant)
  #   2. the GLOBAL row (tenant_id NULL)
  #   3. the declared default in OpenLoam.config_defaults[key]
  #   4. the `default:` argument (nil)
  #
  # Reads are memoized per request in OpenLoam::Current.config_cache, keyed by
  # [key, tenant_id], and the whole cache is dropped on any write. That is the
  # deliberately-simple prototype cache; a Rails.cache-backed layer shared across
  # requests is the scaling path, and it would slot in behind this same API.
  module Configs
    class << self
      def get(key, default: nil)
        key = key.to_s
        store = cache
        cache_key = [key, current_tenant_id]

        return store[cache_key] if store.key?(cache_key)

        # Only a value that actually RESOLVED (a row or a declared default) is
        # cached — never the caller's `default:` fallback. The cache key omits
        # `default:`, so caching it would make a later get with a different
        # default wrongly return the first one when nothing is configured.
        found, value = resolve(key)
        return default unless found

        store[cache_key] = value
      end

      # Write a setting. scope: :tenant writes the current tenant's override and
      # requires a tenant in context (a missing one raises, like every OpenLoam
      # write); scope: :global writes the app-wide row (tenant_id NULL). Upsert.
      def set(key, value, scope: :tenant)
        key = key.to_s
        record = row_for(key, scope).first_or_initialize
        record.value_json = value
        record.save!
        clear_cache
        value
      end

      # Drop the current tenant's override for a key so it falls back to the
      # global row / declared default. Requires a tenant in context. No-op if
      # there was no override. Returns true.
      def reset(key)
        row_for(key.to_s, :tenant).delete_all
        clear_cache
        true
      end

      # Whether the current tenant has an override for this key (vs. inheriting
      # the global/declared value). Drives the admin "overridden?" column.
      def overridden?(key)
        row_for(key.to_s, :tenant).exists?
      end

      # Every key an admin might configure for the current tenant: declared
      # defaults, plus any global or current-tenant rows already written. Sorted
      # and de-duplicated, for the settings screen.
      def defined_keys
        rows = OpenLoam::Config.where(tenant_id: [nil, OpenLoam.tenant&.id]).distinct.pluck(:key)
        (OpenLoam.config_defaults.keys + rows).map(&:to_s).uniq.sort
      end

      private

      # Returns [found?, value]. `found?` is false only when nothing resolved —
      # the caller then applies its own `default:` without caching it.
      def resolve(key)
        if (tenant_id = current_tenant_id)
          override = OpenLoam::Config.find_by(key: key, tenant_id: tenant_id)
          return [true, override.value_json] if override
        end

        global = OpenLoam::Config.find_by(key: key, tenant_id: nil)
        return [true, global.value_json] if global

        return [true, OpenLoam.config_defaults[key]] if OpenLoam.config_defaults.key?(key)

        [false, nil]
      end

      # The row(s) a write/read targets. :global is the tenant_id NULL row;
      # :tenant is the current tenant's — which requires a tenant in context,
      # so OpenLoam.tenant! raises MissingTenantError when there is none.
      def row_for(key, scope)
        case scope
        when :global then OpenLoam::Config.where(key: key, tenant_id: nil)
        when :tenant then OpenLoam::Config.where(key: key, tenant_id: OpenLoam.tenant!.id)
        else raise ArgumentError, "unknown config scope #{scope.inspect} (use :tenant or :global)"
        end
      end

      def current_tenant_id
        OpenLoam.tenant&.id
      end

      def cache
        OpenLoam::Current.config_cache ||= {}
      end

      def clear_cache
        OpenLoam::Current.config_cache = {}
      end
    end
  end
end
