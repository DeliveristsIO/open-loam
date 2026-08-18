module Loam
  class Engine < ::Rails::Engine
    # Not isolated on purpose: Loam models live under the Loam:: namespace but
    # share the host app's routes/helpers, keeping the prototype surface small.

    # lib/tasks/loam.rake (bin/rails loam:sync) is picked up by Rails::Engine's
    # own lib/tasks loading. Loading it again from a `rake_tasks` block here
    # would define the task twice and run its body twice.
  end
end
