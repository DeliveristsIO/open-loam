module OpenLoam
  # Base class for every tenant-scoped model. Inheriting from it is what makes
  # a model a "OpenLoam entity":
  #
  #   * every query is scoped to OpenLoam::Current.tenant via default_scope
  #   * building/creating a record assigns the current tenant automatically
  #   * touching the model with NO tenant in context raises MissingTenantError
  #
  # Escape hatch: `Model.unscoped` skips the scope. It is deliberately the
  # standard Rails spelling so it is trivially greppable in review, and
  # AGENTS.md forbids agents from using it.
  class TenantRecord < ActiveRecord::Base
    self.abstract_class = true

    # Generates the key when it is not an integer (see OpenLoam::GeneratedKey).
    include OpenLoam::GeneratedKey

    belongs_to :tenant, class_name: "OpenLoam::Tenant"

    default_scope { where(tenant_id: OpenLoam.tenant!.id) }

    validates :tenant_id, presence: true

    before_validation on: :create do
      self.tenant_id ||= OpenLoam.tenant!.id
    end

    # Guardrail for writes: a record can never be saved into a foreign tenant.
    before_save do
      if tenant_id != OpenLoam.tenant!.id
        raise MissingTenantError, "Attempted to write #{self.class.name} into tenant #{tenant_id} " \
                                  "while OpenLoam::Current.tenant is #{OpenLoam.tenant!.id}"
      end
    end
  end
end
