# Tenant-scoped, audited, evented — by inheritance, not by remembering.
class <%= class_name %> < Loam::TenantRecord
  include Loam::Auditable
  include Loam::Eventful
  include Loam::CustomFields
  include Loam::Commentable
  include Loam::Attachable
  include Loam::Searchable
  include Loam::SoftDeletable

  event_domain :<%= domain %>
<% if searchable_attributes.any? -%>
  searchable_by <%= searchable_attributes.map { |a| ":#{a.name}" }.join(", ") %>
<% end -%>

  # Business logic goes here. Publish business events explicitly:
  #   Loam::Events.publish("<%= domain %>.something.happened", id: id)
end
