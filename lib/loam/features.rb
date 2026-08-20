module Loam
  # Runtime feature toggles: is a capability turned ON for this tenant right now.
  #
  #   Loam::Features.on?(:beta_dashboard)          # for the current tenant
  #   Loam::Features.enable(:beta_dashboard)       # this tenant only
  #   Loam::Features.enable(:beta_dashboard, scope: :global)  # everyone
  #   Loam::Features.disable(:beta_dashboard)
  #   Loam::Features.reset(:beta_dashboard)        # drop the override → default
  #
  # A flag gates a CAPABILITY (is this feature live for the tenant), which is
  # orthogonal to a policy — that gates a PERSON (may this user act). The two
  # coexist: a manager may be allowed to approve reports AND the approvals
  # feature may be switched off for their tenant during a rollout.
  #
  # This is deliberately a thin wrapper over Loam::Configs: a flag is a boolean
  # setting with the same override → global → declared-default resolution, so it
  # reuses that store (no new table) and its per-request cache. Flags live under
  # the reserved `features.` key prefix and get their own admin screen, because
  # "flags" and "settings" are different mental models even sharing storage.
  module Features
    PREFIX = "features.".freeze

    class << self
      def on?(name)
        !!Loam::Configs.get(key_for(name), default: default_for(name))
      end

      def off?(name)
        !on?(name)
      end

      # Flip a flag on. scope: :tenant (default) overrides for the current tenant
      # and requires a tenant in context; scope: :global sets the app-wide state.
      def enable(name, scope: :tenant)
        Loam::Configs.set(key_for(name), true, scope: scope)
      end

      def disable(name, scope: :tenant)
        Loam::Configs.set(key_for(name), false, scope: scope)
      end

      # Drop the current tenant's override so the flag falls back to the global
      # state / declared default.
      def reset(name)
        Loam::Configs.reset(key_for(name))
      end

      def overridden?(name)
        Loam::Configs.overridden?(key_for(name))
      end

      # Every declared flag, sorted — the admin lists these whether or not a row
      # exists yet, so a flag is visible the moment it is declared.
      def declared
        Loam.feature_defaults.keys.sort
      end

      def description(name)
        Loam.feature_defaults.dig(name.to_s, :description)
      end

      # The declared-default state of a flag (false for an unknown one), used as
      # the last resort when there is no override and no global row.
      def default_for(name)
        !!Loam.feature_defaults.dig(name.to_s, :default)
      end

      private

      def key_for(name)
        "#{PREFIX}#{name}"
      end
    end
  end
end
