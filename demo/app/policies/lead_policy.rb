class LeadPolicy < Loam::Policy
  # Anyone at the branch works the pipeline, but the deal value is a manager's
  # number — an employee sees it, can't change it (the same field-level rule the
  # rental domain uses for daily_rate).
  field :value, writable: [ :manager ]

  def destroy? = role == :manager
end
