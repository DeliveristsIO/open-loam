module Loam
  # Audit-by-default. Included in every generated entity: create/update/destroy
  # writes a Loam::AuditRecord tagged with tenant + actor + changeset. "Who
  # changed the excavator's price, and when" is answered structurally, not by
  # remembering to log.
  module Auditable
    extend ActiveSupport::Concern

    IGNORED_ATTRIBUTES = %w[updated_at created_at].freeze

    included do
      after_create  { loam_audit("create") }
      after_update  { loam_audit("update") if loam_audit_changes.any? }
      after_destroy { loam_audit("destroy") }
    end

    private

    def loam_audit(action)
      Loam::AuditRecord.create!(
        auditable_type: self.class.name,
        auditable_id: id,
        action: action,
        actor_id: Loam::Current.actor&.id,
        changeset: action == "destroy" ? {} : loam_audit_changes
      )
    end

    def loam_audit_changes
      saved_changes.except(*IGNORED_ATTRIBUTES)
    end
  end
end
