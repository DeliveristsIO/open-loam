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

    # Loam's Active Record layer — TenantRecord, Auditable, Eventful and the
    # rest — is defined inside ActiveSupport.on_load(:active_record) in
    # lib/loam.rb, so those constants exist only once something has referenced
    # ActiveRecord::Base.
    #
    # Zeitwerk eager-loads app/models alphabetically. A host model that inherits
    # from Loam::TenantRecord and sorts ahead of application_record.rb reaches
    # the constant before anything has touched Base, and eager load dies with
    # "uninitialized constant Loam::TenantRecord". Whether an app hits it
    # depends on its model names, so it shows up on a rename rather than on the
    # change that caused it.
    #
    # Referencing Base here fires the hook while load order is still the
    # engine's to decide instead of each host app's. :eager_load! is late enough
    # that every active_record.* initializer has applied its configuration, and
    # it runs in every environment (in development it is a no-op that still
    # executes), so lazily-loaded apps are settled by the same line.
    initializer "loam.active_record_layer", before: :eager_load! do
      ActiveRecord::Base
    end

    # Loam's own UI strings ship under lib/ (the gemspec packages lib/**/*), so
    # register them on the app's I18n load path explicitly rather than relying on
    # the default config/locales path (which the gem does not ship). An app
    # overrides any key with its own config/locales/loam.<locale>.yml.
    initializer "loam.i18n" do |app|
      app.config.i18n.load_path += Dir[File.expand_path("locales/*.yml", __dir__)]
    end

    # lib/tasks/loam.rake (bin/rails loam:sync) is picked up by Rails::Engine's
    # own lib/tasks loading. Loading it again from a `rake_tasks` block here
    # would define the task twice and run its body twice.
  end
end
