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
      class_attribute :loam_event_entity, default: nil

      after_create_commit  { publish_lifecycle_event("created") }
      after_update_commit  { publish_lifecycle_event("updated") }
      after_destroy_commit { publish_lifecycle_event("destroyed") }
    end

    class_methods do
      def event_domain(domain)
        self.loam_event_domain = domain.to_s
      end

      # The middle segment of the event name. It defaults to the model's param
      # key, which is right for app models but awkward for namespaced ones —
      # Loam::Comment would publish "loam.loam_comment.created" rather than
      # "loam.comment.created".
      def event_entity(name)
        self.loam_event_entity = name.to_s
      end
    end

    private

    def publish_lifecycle_event(happened)
      Loam::Events.publish(
        "#{loam_event_domain}.#{loam_event_entity || model_name.param_key}.#{happened}",
        { id: id, type: self.class.name }
      )
    end
  end
end
