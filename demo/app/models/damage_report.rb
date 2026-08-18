# Tenant-scoped, audited, evented — by inheritance, not by remembering.
class DamageReport < Loam::TenantRecord
  include Loam::Auditable
  include Loam::Eventful
  include Loam::CustomFields

  event_domain :rental

  # Business logic goes here. Publish business events explicitly:
  #   Loam::Events.publish("rental.something.happened", id: id)

  # An approved damage report triggers a penalty charge.
  after_update_commit :publish_penalty_due, if: -> { saved_change_to_approved? && approved? }

  private

  def publish_penalty_due
    Loam::Events.publish("billing.penalty.due", id: id)
  end
end
