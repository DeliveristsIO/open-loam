module Loam
  class Engine < ::Rails::Engine
    # Not isolated on purpose: Loam models live under the Loam:: namespace but
    # share the host app's routes/helpers, keeping the prototype surface small.
  end
end
