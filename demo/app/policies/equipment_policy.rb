class EquipmentPolicy < OpenLoam::Policy
  # Any member of the tenant may read and manage equipment records, but the rate
  # card is manager-only — not just to write, to SEE. One declaration; the admin
  # index/show/form, the JSON API, the CSV export and the controller permit list
  # all obey it.
  field :daily_rate, writable: [:manager], readable: [:manager]

  def destroy? = role == :manager
end
