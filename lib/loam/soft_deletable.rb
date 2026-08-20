module Loam
  # Soft-delete: destroying a business record hides it instead of erasing it.
  # A recycle bin — for GDPR retention, for undo, for audits that still read
  # cleanly after the fact. Loam is "safe by default", so a soft-deleted record
  # is EXCLUDED from every ordinary query; seeing it is something you opt INTO,
  # never a filter you must remember to add.
  #
  #   equipment.soft_delete    # deleted_at = now; gone from Equipment.all
  #   Equipment.with_deleted   # includes it — but STILL tenant-scoped
  #   Equipment.only_deleted   # just the recycle bin
  #   equipment.restore        # deleted_at = nil; back in every query
  #   equipment.destroy        # the real erase — the row leaves the database
  #
  # `destroy` still hard-deletes, for a genuine "forget me". The generated admin
  # calls `soft_delete`, so its delete button is undoable; reach for `destroy`
  # only when the row must actually leave the database.
  module SoftDeletable
    extend ActiveSupport::Concern

    included do
      # A second default_scope: Rails ANDs it with TenantRecord's tenant scope,
      # so a hidden record is invisible AND still tenant-isolated.
      default_scope { where(deleted_at: nil) }

      # `unscope`, never `unscoped`: this drops ONLY the deleted_at predicate and
      # keeps the tenant_id one, so the recycle bin can never surface another
      # tenant's rows. `unscoped` would drop both and is forbidden here.
      scope :with_deleted, -> { unscope(where: :deleted_at) }
      scope :only_deleted, -> { with_deleted.where.not(deleted_at: nil) }
    end

    def deleted?
      deleted_at.present?
    end

    def soft_delete
      loam_toggle_deleted(deleted: true, bang: false)
    end

    def soft_delete!
      loam_toggle_deleted(deleted: true, bang: true)
    end

    def restore
      loam_toggle_deleted(deleted: false, bang: false)
    end

    def restore!
      loam_toggle_deleted(deleted: false, bang: true)
    end

    private

    # One write for all four entry points. Idempotent by design: toggling a
    # record to the state it is already in (a double-clicked button) is a no-op,
    # so the trail never fills with deleted_at -> deleted_at noise.
    #
    # A soft-delete is an UPDATE, so Loam::Auditable's after_destroy never fires
    # for it. Rather than write our own audit row we borrow Auditable's single
    # audit path via `loam_audit_as`, which relabels this save's audit
    # "soft_delete"/"restore" instead of the "update" it would otherwise record.
    def loam_toggle_deleted(deleted:, bang:)
      return true if deleted == deleted?

      self.deleted_at = deleted ? Time.current : nil
      action = deleted ? "soft_delete" : "restore"
      write = -> { bang ? save! : save }

      respond_to?(:loam_audit_as, true) ? loam_audit_as(action, &write) : write.call
    end
  end
end
