# Tenant-scoped, audited, evented — by inheritance, not by remembering.
class Company < OpenLoam::TenantRecord
  include OpenLoam::Auditable
  include OpenLoam::Eventful
  include OpenLoam::CustomFields
  include OpenLoam::Commentable
  include OpenLoam::Attachable
  include OpenLoam::Searchable
  include OpenLoam::SoftDeletable

  event_domain :crm
  searchable_by :name, :industry, :tier

  # Business logic goes here. Publish business events explicitly:
  #   OpenLoam::Events.publish("crm.something.happened", id: id)
end
