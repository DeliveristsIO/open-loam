# Tenant-scoped, audited, evented — by inheritance, not by remembering.
class <%= class_name %> < OpenLoam::TenantRecord
  include OpenLoam::Auditable
  include OpenLoam::Eventful
  include OpenLoam::CustomFields
  include OpenLoam::Commentable
  include OpenLoam::Attachable
  include OpenLoam::Searchable
  include OpenLoam::SoftDeletable
<% if encrypted_field_names.any? -%>
  include OpenLoam::Encryptable
<% end -%>

  event_domain :<%= domain %>
<% if searchable_attributes.any? -%>
  searchable_by <%= searchable_attributes.map { |a| ":#{a.name}" }.join(", ") %>
<% end -%>
<% options[:encrypt].each do |field| -%>
  encrypts :<%= field %>
<% end -%>
<% encrypt_searchable_names.each do |field| -%>
  encrypts :<%= field %>, searchable: true   # exact-match lookup via <%= field %>_hash
<% end -%>

  # Business logic goes here. Publish business events explicitly:
  #   OpenLoam::Events.publish("<%= domain %>.something.happened", id: id)
end
