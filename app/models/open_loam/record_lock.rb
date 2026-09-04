module Loam
  # An advisory "someone is editing this" lock on a record — the COURTESY layer.
  # The real guarantee against a silent clobber is optimistic locking
  # (lock_version, see Loam::RecordLocks docs); this only warns the second
  # editor. One lock per record, with a TTL: an expired lock is treated as free,
  # and re-acquiring as the same holder extends it (a heartbeat). Plumbing, so
  # not audited — like Loam::ApiToken.
  class RecordLock < Loam::TenantRecord
    self.table_name = "loam_record_locks"

    belongs_to :locked_by, class_name: "User"

    validates :lockable_type, :lockable_id, :token, :expires_at, presence: true

    def expired?
      expires_at.nil? || expires_at <= Time.current
    end
  end
end
