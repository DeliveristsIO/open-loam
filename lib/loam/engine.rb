module Loam
  class Engine < ::Rails::Engine
    # Not isolated on purpose: Loam models live under the Loam:: namespace but
    # share the host app's routes/helpers, keeping the prototype surface small.

    # Webhook dispatch listens to every Loam event. Wired after initialization
    # so the models it queries are loadable, and guarded against subscribing
    # twice (see Loam::Webhooks.subscribe!).
    config.after_initialize do
      Loam::Webhooks.subscribe!
      Loam::DurableEvents.subscribe!    # persist + retry durable subscribers (L-706)
      Loam::BusinessRules.subscribe!
      Loam::Widgets.register_builtins!  # the default dashboard widgets
      Loam::Overrides.check!            # warn about any stale disable/replace overrides

      # The durability sweep runs per-tenant on a schedule (materialized into
      # each tenant by Loam::Scheduler.sync_tenant). interval:300 = every 5 min.
      Loam::Scheduler.register(
        key: Loam::DurableEvents::SWEEP_KEY, name: "Event redelivery sweep",
        job_class: "Loam::EventRedeliverySweepJob", schedule: "interval:300", scope: "tenant"
      )
    end

    # lib/tasks/loam.rake (bin/rails loam:sync) is picked up by Rails::Engine's
    # own lib/tasks loading. Loading it again from a `rake_tasks` block here
    # would define the task twice and run its body twice.
  end
end
