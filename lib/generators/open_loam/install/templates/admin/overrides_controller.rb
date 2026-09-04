module Admin
  # Read-only view of the app's Loam::Overrides — which registry entries are
  # disabled or replaced, plus any STALE overrides (a key that no longer exists).
  # Manager-only, for legibility: it's config declared in an initializer, shown
  # here so an operator can see what's been customized without reading code.
  class OverridesController < BaseController
    before_action { require_role!(:manager) }

    def index
      @overrides = Loam::Overrides.all
      @stale = Loam::Overrides.stale
    end
  end
end
