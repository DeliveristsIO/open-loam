module OpenLoam
  # Mixed into ActiveSupport::TestCase by the install generator.
  module TestHelpers
    extend ActiveSupport::Concern

    included do
      setup { OpenLoam::Current.reset }
      teardown { OpenLoam::Current.reset }
    end

    def with_tenant(tenant, actor: nil, &block)
      OpenLoam.as_tenant(tenant, actor: actor, &block)
    end
  end
end
