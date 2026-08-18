module Loam
  # Mixed into ActiveSupport::TestCase by the install generator.
  module TestHelpers
    extend ActiveSupport::Concern

    included do
      setup { Loam::Current.reset }
      teardown { Loam::Current.reset }
    end

    def with_tenant(tenant, actor: nil, &block)
      Loam.as_tenant(tenant, actor: actor, &block)
    end
  end
end
