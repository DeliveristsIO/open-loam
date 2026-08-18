# Tenant-scoped, audited, evented — by inheritance, not by remembering.
class Equipment < Loam::TenantRecord
  include Loam::Auditable
  include Loam::Eventful
  include Loam::CustomFields

  event_domain :rental

  # Business logic goes here. Publish business events explicitly:
  #   Loam::Events.publish("rental.something.happened", id: id)
end
