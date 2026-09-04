# Tenant-scoped, audited, evented — by inheritance, not by remembering.
class Equipment < OpenLoam::TenantRecord
  include OpenLoam::Auditable
  include OpenLoam::Eventful
  include OpenLoam::CustomFields
  include OpenLoam::Commentable
  include OpenLoam::Attachable
  include OpenLoam::Searchable
  include OpenLoam::SoftDeletable
  include OpenLoam::Translatable

  event_domain :rental
  searchable_by :name, :status
  translates :name  # per-locale content overlay over the base name (OpenLoam::Translatable)

  # Business logic goes here. Publish business events explicitly:
  #   OpenLoam::Events.publish("rental.something.happened", id: id)
end
