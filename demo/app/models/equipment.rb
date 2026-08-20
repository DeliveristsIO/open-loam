# Tenant-scoped, audited, evented — by inheritance, not by remembering.
class Equipment < Loam::TenantRecord
  include Loam::Auditable
  include Loam::Eventful
  include Loam::CustomFields
  include Loam::Commentable
  include Loam::Attachable
  include Loam::Searchable
  include Loam::SoftDeletable

  event_domain :rental
  searchable_by :name, :status

  # Business logic goes here. Publish business events explicitly:
  #   Loam::Events.publish("rental.something.happened", id: id)
end
