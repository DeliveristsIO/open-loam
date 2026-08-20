# Tenant-scoped, audited, evented — by inheritance, not by remembering.
class Customer < Loam::TenantRecord
  include Loam::Auditable
  include Loam::Eventful
  include Loam::CustomFields
  include Loam::Commentable
  include Loam::Attachable
  include Loam::Searchable
  include Loam::SoftDeletable
  include Loam::Encryptable

  event_domain :rental
  searchable_by :name
  encrypts :tax_id
  encrypts :email, searchable: true   # exact-match lookup via email_hash

  # Business logic goes here. Publish business events explicitly:
  #   Loam::Events.publish("rental.something.happened", id: id)
end
