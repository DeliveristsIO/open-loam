# Tenant-scoped, audited, evented — by inheritance, not by remembering.
class Company < Loam::TenantRecord
  include Loam::Auditable
  include Loam::Eventful
  include Loam::CustomFields
  include Loam::Commentable
  include Loam::Attachable
  include Loam::Searchable
  include Loam::SoftDeletable

  event_domain :crm
  searchable_by :name, :industry, :tier

  # Business logic goes here. Publish business events explicitly:
  #   Loam::Events.publish("crm.something.happened", id: id)
end
