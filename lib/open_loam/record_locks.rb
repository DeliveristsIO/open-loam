module Loam
  # Advisory record locks (Loam::RecordLock) — a "who's editing this" courtesy
  # for the multi-user admin.
  #
  #   Loam::RecordLocks.acquire(record, by: current_actor)  # take/refresh, or nil if held
  #   Loam::RecordLocks.holder(record)                      # the user holding it, or nil
  #   Loam::RecordLocks.release(record, by: current_actor)  # give it up
  #   Loam::RecordLocks.force_release(record)               # manager override
  #
  # THIS IS ADVISORY: a held lock warns, it does not hard-block — optimistic
  # locking (lock_version) is the actual guarantee that two edits can't clobber.
  # Every query is tenant-scoped by Loam::RecordLock, so a lock is invisible and
  # unaffectable from another tenant.
  module RecordLocks
    DEFAULT_TTL = 5.minutes

    class << self
      # Take or refresh the lock if it is free (or already yours). The same
      # holder re-acquiring extends the TTL (heartbeat). Returns the lock, or nil
      # when someone else holds a live one. A record that no longer exists
      # (hard- or soft-deleted) cannot be locked.
      def acquire(record, by:, ttl: DEFAULT_TTL)
        return nil unless present?(record)

        lock = lock_row(record)
        return nil if lock && !lock.expired? && lock.locked_by_id != by.id

        lock ||= Loam::RecordLock.new(lockable_type: type_of(record), lockable_id: record.id)
        # A fresh session token when the lock is newly created or taken over from
        # an expired holder; kept as-is on a heartbeat by the same user.
        lock.token = SecureRandom.hex(16) if lock.new_record? || lock.locked_by_id != by.id
        lock.locked_by_id = by.id
        lock.expires_at = Time.current + ttl
        lock.save!
        lock
      rescue ActiveRecord::RecordNotUnique
        # Lost the create race — someone else got it first, which is exactly the
        # nil contract. Advisory honesty over cleverness.
        nil
      end

      # The live lock on a record, or nil — cleaning up a lock that is expired or
      # whose record is gone (an auto-free), so orphaned rows don't linger.
      def active_lock(record)
        lock = lock_row(record)
        return nil unless lock

        if lock.expired? || !present?(record)
          lock.destroy
          return nil
        end
        lock
      end

      def holder(record)
        active_lock(record)&.locked_by
      end

      def release(record, by:)
        lock = lock_row(record)
        lock.destroy if lock && lock.locked_by_id == by.id
        true
      end

      # Manager override: drop whoever holds it. The controller gates the role.
      def force_release(record)
        lock_row(record)&.destroy
        true
      end

      private

      def lock_row(record)
        Loam::RecordLock.find_by(lockable_type: type_of(record), lockable_id: record.id)
      end

      def type_of(record)
        record.class.base_class.name
      end

      # Does the record still exist in the ordinary (non-soft-deleted) scope? A
      # soft-deleted or hard-deleted record is "gone", so its lock auto-frees.
      # Runs under the tenant default scope, which every call site has.
      def present?(record)
        record.class.base_class.where(id: record.id).exists?
      end
    end
  end
end
