module OpenLoam
  # Audit-by-default. Included in every generated entity: create/update/destroy
  # writes a OpenLoam::AuditRecord tagged with tenant + actor + changeset. "Who
  # changed the excavator's price, and when" is answered structurally, not by
  # remembering to log.
  module Auditable
    extend ActiveSupport::Concern

    IGNORED_ATTRIBUTES = %w[updated_at created_at].freeze

    included do
      after_create  { open_loam_audit("create") }
      after_update  { open_loam_audit(open_loam_audit_action) if open_loam_audit_changes.any? }
      after_destroy { open_loam_audit("destroy") }
    end

    private

    # Relabel the audit that the save inside the block writes. OpenLoam::SoftDeletable
    # uses this to record a soft-delete (an UPDATE) as "soft_delete"/"restore"
    # rather than the "update" it would otherwise be — one audit path, reused,
    # not a second one to keep in sync.
    def open_loam_audit_as(action)
      previous = @open_loam_audit_action
      @open_loam_audit_action = action
      yield
    ensure
      @open_loam_audit_action = previous
    end

    def open_loam_audit_action
      @open_loam_audit_action || "update"
    end

    def open_loam_audit(action)
      OpenLoam::AuditRecord.create!(
        auditable_type: self.class.name,
        auditable_id: id,
        action: action,
        actor_id: OpenLoam::Current.actor&.id,
        changeset: action == "destroy" ? {} : open_loam_audit_changes
      )
    end

    def open_loam_audit_changes
      changes = saved_changes.except(*IGNORED_ATTRIBUTES)
      open_loam_redact_encrypted(changes)
    end

    # The audit trail must record the FACT that an encrypted field changed, never
    # its value — neither the plaintext nor the ciphertext (a ciphertext still
    # leaks length and, over time, correlations). So an encrypted column's change
    # becomes "[encrypted]", and its blind-index sibling is dropped entirely.
    # A no-op for models without OpenLoam::Encryptable.
    def open_loam_redact_encrypted(changes)
      return changes unless self.class.respond_to?(:open_loam_encrypted_attributes)

      encrypted = self.class.open_loam_encrypted_attributes.map(&:to_s)
      hash_columns = self.class.open_loam_searchable_encrypted_attributes.map { |name| "#{name}_hash" }

      changes.each_with_object({}) do |(column, values), redacted|
        next if hash_columns.include?(column)
        redacted[column] = encrypted.include?(column) ? "[encrypted]" : values
      end
    end
  end
end
