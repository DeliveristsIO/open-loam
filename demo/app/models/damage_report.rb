# Tenant-scoped, audited, evented — by inheritance, not by remembering.
class DamageReport < OpenLoam::TenantRecord
  include OpenLoam::Auditable
  include OpenLoam::Eventful
  include OpenLoam::CustomFields
  include OpenLoam::Commentable
  include OpenLoam::Attachable
  include OpenLoam::Searchable
  include OpenLoam::SoftDeletable
  include OpenLoam::Workflow

  event_domain :rental
  searchable_by :description, :state

  # A damage report is filed by anyone on site, but only a manager decides what
  # happens to it. The states live in `state`; the older `approved` boolean is
  # the billing flag and is left alone on purpose — note that `report.approved?`
  # therefore still reads that column, not the workflow state (OpenLoam::Workflow
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
  #   OpenLoam::Events.publish("rental.something.happened", id: id)

  # An approved damage report triggers a penalty charge.
  after_update_commit :publish_penalty_due, if: -> { saved_change_to_approved? && approved? }

  private

  def publish_penalty_due
    OpenLoam::Events.publish("billing.penalty.due", id: id)
  end

  # A business rule with a `block_transition` action can veto a workflow move
  # (OpenLoam::BusinessRules.veto?) — checked BEFORE the transition runs. This wiring
  # is an example; other entities can adopt it the same way. The class def wins
  # over OpenLoam::Workflow's method and reaches it via super.
  def open_loam_perform_transition!(transition)
    trigger = "#{open_loam_workflow_event_domain}.#{model_name.param_key}.#{transition.name}"
    if OpenLoam::BusinessRules.veto?(self, trigger)
      raise OpenLoam::TransitionVetoedError, "#{model_name.human} #{transition.name} was vetoed by a business rule"
    end

    super
  end
end
