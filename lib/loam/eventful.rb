module Loam
  # Lifecycle events by convention. Included in every generated entity:
  #
  #   class Equipment < Loam::TenantRecord
  #     include Loam::Eventful
  #     event_domain :rental          # -> "rental.equipment.created" etc.
  #   end
  #
  # Custom business events are published explicitly with Loam::Events.publish.
  module Eventful
    extend ActiveSupport::Concern

    included do
      class_attribute :loam_event_domain, default: "app"

      after_create_commit  { publish_lifecycle_event("created") }
      after_update_commit  { publish_lifecycle_event("updated") }
      after_destroy_commit { publish_lifecycle_event("destroyed") }
    end

    class_methods do
      def event_domain(domain)
        self.loam_event_domain = domain.to_s
      end
    end

    private

    def publish_lifecycle_event(happened)
      Loam::Events.publish(
        "#{loam_event_domain}.#{model_name.param_key}.#{happened}",
        { id: id, type: self.class.name }
      )
    end
  end
end
