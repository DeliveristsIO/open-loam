module Loam
  class Engine < ::Rails::Engine
    # Not isolated on purpose: Loam models live under the Loam:: namespace but
    # share the host app's routes/helpers, keeping the prototype surface small.

    # Webhook dispatch listens to every Loam event. Wired after initialization
    # so the models it queries are loadable, and guarded against subscribing
    # twice (see Loam::Webhooks.subscribe!).
    config.after_initialize do
      Loam::Webhooks.subscribe!
    end

    # lib/tasks/loam.rake (bin/rails loam:sync) is picked up by Rails::Engine's
    # own lib/tasks loading. Loading it again from a `rake_tasks` block here
    # would define the task twice and run its body twice.
  end
end
