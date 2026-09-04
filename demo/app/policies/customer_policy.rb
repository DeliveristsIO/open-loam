class CustomerPolicy < OpenLoam::Policy
  # Action defaults: any member of the current tenant may read/create/update/
  # destroy. Tighten by overriding, e.g.:
  #
  #   def destroy? = role == :manager
  #
  # Field-level write access is declared, not coded:
  #
  #   field :name, writable: [:manager]
end
