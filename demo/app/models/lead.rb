# A CRM sales lead — the SAME primitives that run the rental domain, in a
# different domain: tenant-scoped, audited, evented, with a role-gated pipeline
# workflow. Proof that Loam is domain-agnostic (L-501).
class Lead < Loam::TenantRecord
  include Loam::Auditable
  include Loam::Eventful
  include Loam::CustomFields
  include Loam::Commentable
  include Loam::Attachable
  include Loam::Searchable
  include Loam::SoftDeletable
  include Loam::Workflow

  belongs_to :company, optional: true

  event_domain :crm
  searchable_by :source, :state

  # The sales pipeline. Advancing is open to any member; CLOSING a lead (won or
  # lost) is a manager decision — the same role-gated transition the rental
  # domain uses for damage-report approval, no new mechanism.
  workflow :state, initial: "new" do
    state "new"
    state "qualified"
    state "won"
    state "lost"

    transition :qualify, from: "new",       to: "qualified"
    transition :win,     from: "qualified", to: "won",  roles: [ :manager ]
    transition :lose,    from: "qualified", to: "lost", roles: [ :manager ]
  end
end
