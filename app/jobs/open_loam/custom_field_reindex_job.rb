module OpenLoam
  # Heals a custom-field index gap in the background: rebuilds one model's
  # read-model index (OpenLoam::CustomFieldIndex) for one tenant. Enqueued (deduped)
  # by CustomFieldIndex when a filter/order runs over an incomplete index, so a
  # gap self-heals without an operator running a rake task. Inherits
  # ActiveJob::Base, not the app's ApplicationRecord-owned base (the gem must not
  # depend on a class the app configures), and carries the tenant explicitly.
  class CustomFieldReindexJob < ActiveJob::Base
    queue_as :default

    def perform(tenant_id, model_name)
      tenant = OpenLoam::Tenant.find_by(id: tenant_id)
      model = model_name.to_s.safe_constantize
      return unless tenant && model.is_a?(Class) && model < OpenLoam::TenantRecord

      OpenLoam.as_tenant(tenant) { OpenLoam::CustomFieldIndex.reindex(model) }
    ensure
      # Release the dedup marker so a later real gap can enqueue again.
      OpenLoam::CustomFieldIndex.clear_pending(tenant_id, model_name.to_s)
    end
  end
end
