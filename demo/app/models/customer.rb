# Tenant-scoped, audited, evented — by inheritance, not by remembering.
class Customer < OpenLoam::TenantRecord
  include OpenLoam::Auditable
  include OpenLoam::Eventful
  include OpenLoam::CustomFields
  include OpenLoam::Commentable
  include OpenLoam::Attachable
  include OpenLoam::Searchable
  include OpenLoam::SoftDeletable
  include OpenLoam::Encryptable

  event_domain :rental
  searchable_by :name
  encrypts :tax_id
  encrypts :email, searchable: true   # exact-match lookup via email_hash

  # Business logic goes here. Publish business events explicitly:
  #   OpenLoam::Events.publish("rental.something.happened", id: id)
end
