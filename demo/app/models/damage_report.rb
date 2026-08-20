# Tenant-scoped, audited, evented — by inheritance, not by remembering.
class DamageReport < Loam::TenantRecord
  include Loam::Auditable
  include Loam::Eventful
  include Loam::CustomFields
  include Loam::Commentable
  include Loam::Attachable
  include Loam::Searchable
  include Loam::SoftDeletable
  include Loam::Workflow

  event_domain :rental
  searchable_by :description, :state

  # A damage report is filed by anyone on site, but only a manager decides what
  # happens to it. The states live in `state`; the older `approved` boolean is
  # the billing flag and is left alone on purpose — note that `report.approved?`
  # therefore still reads that column, not the workflow state (Loam::Workflow
  # skips a predicate that would shadow a column).
  workflow :state, initial: "open" do
    state "open"
    state "pending_approval"
    state "approved"
    state "rejected"

    transition :submit,  from: "open",             to: "pending_approval"
    transition :approve, from: "pending_approval", to: "approved", roles: [ :manager ]
    transition :reject,  from: "pending_approval", to: "rejected", roles: [ :manager ]
  end

  # Business logic goes here. Publish business events explicitly:
  #   Loam::Events.publish("rental.something.happened", id: id)

  # An approved damage report triggers a penalty charge.
  after_update_commit :publish_penalty_due, if: -> { saved_change_to_approved? && approved? }

  private

  def publish_penalty_due
    Loam::Events.publish("billing.penalty.due", id: id)
  end
end
