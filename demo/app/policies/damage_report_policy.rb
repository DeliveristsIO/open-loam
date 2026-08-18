class DamageReportPolicy < Loam::Policy
  # Action defaults: any member of the current tenant may read/create/update/
  # destroy. Tighten by overriding, e.g.:
  #
  #   def destroy? = role == :manager
  #
  # Field-level write access is declared, not coded:
  #
  #   field :equipment_id, writable: [:manager]

  # Only a manager may approve a damage report.
  field :approved, writable: [:manager]
end
