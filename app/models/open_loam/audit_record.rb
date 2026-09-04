module Loam
  # One row per change: who (actor), what (auditable + action + changeset),
  # when (created_at), in which tenant (tenant_id, via TenantRecord).
  # Append-only by convention; not itself audited or evented.
  class AuditRecord < Loam::TenantRecord
    self.table_name = "loam_audit_records"

    belongs_to :actor, class_name: "User", optional: true

    validates :auditable_type, :auditable_id, :action, presence: true

    serialize :changeset, coder: JSON

    def auditable
      auditable_type.constantize.unscoped.find_by(id: auditable_id)
    end
  end
end
