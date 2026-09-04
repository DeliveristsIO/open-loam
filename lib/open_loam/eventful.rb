module OpenLoam
  # Lifecycle events by convention. Included in every generated entity:
  #
  #   class Equipment < OpenLoam::TenantRecord
  #     include OpenLoam::Eventful
  #     event_domain :rental          # -> "rental.equipment.created" etc.
  #   end
  #
  # Custom business events are published explicitly with OpenLoam::Events.publish.
  module Eventful
    extend ActiveSupport::Concern

    included do
      class_attribute :open_loam_event_domain, default: "app"
      class_attribute :open_loam_event_entity, default: nil

      after_create_commit  { publish_lifecycle_event("created") }
      after_update_commit  { publish_lifecycle_event("updated") }
      after_destroy_commit { publish_lifecycle_event("destroyed") }
    end

    class_methods do
      def event_domain(domain)
        self.open_loam_event_domain = domain.to_s
      end

      # The middle segment of the event name. It defaults to the model's param
      # key, which is right for app models but awkward for namespaced ones —
      # OpenLoam::Comment would publish "open_loam.open_loam_comment.created" rather than
      # "open_loam.comment.created".
      def event_entity(name)
        self.open_loam_event_entity = name.to_s
      end
    end

    private

    def publish_lifecycle_event(happened)
      OpenLoam::Events.publish(
        "#{open_loam_event_domain}.#{open_loam_event_entity || model_name.param_key}.#{happened}",
        { id: id, type: self.class.name }
      )
    end
  end
end
