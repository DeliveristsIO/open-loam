# Tenant-scoped, audited, evented — by inheritance, not by remembering.
class <%= class_name %> < Loam::TenantRecord
  include Loam::Auditable
  include Loam::Eventful
  include Loam::CustomFields

  event_domain :<%= domain %>

  # Business logic goes here. Publish business events explicitly:
  #   Loam::Events.publish("<%= domain %>.something.happened", id: id)
end
