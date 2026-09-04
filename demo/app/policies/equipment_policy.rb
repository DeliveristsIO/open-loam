class EquipmentPolicy < OpenLoam::Policy
  # Any member of the tenant may read and manage equipment records, but only
  # a manager can touch the money. One declaration — the admin form and the
  # controller permit list both obey it.
  field :daily_rate, writable: [:manager]

  def destroy? = role == :manager
end
