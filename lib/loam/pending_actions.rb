module Loam
  # Staging and reviewing gated mutations (see Loam::PendingAction).
  #
  #   pending = Loam::PendingActions.stage(
  #     summary: "Raise the excavator's daily rate to 1100",
  #     on: equipment, action: :update, changes: { daily_rate: 1100 }
  #   )
  #   pending.preview            # => { "daily_rate" => { "from" => 950, "to" => 1100 } }
  #   pending.approve!(by: manager)   # role-gated; executes the change
  #
  # `stage` NEVER touches the target — it only records the intent. Loam does not
  # intercept Active Record globally (that would be fragile and out of scope);
  # this is the primitive a confirm-mode write path calls instead of saving.
  module PendingActions
    class << self
      def stage(summary:, on:, action:, changes: {}, idempotency_key: nil, actor: Loam::Current.actor)
        target_type, target_id = resolve_target(on)
        changes = changes.transform_keys(&:to_s)
        key = idempotency_key || compute_key(target_type, target_id, action, changes)

        # The same proposal staged twice collapses to one row — return the
        # existing one rather than a duplicate. The unique index is the backstop
        # for a concurrent double-stage (the rescue below).
        existing = Loam::PendingAction.find_by(idempotency_key: key)
        return existing if existing

        Loam::PendingAction.create!(
          actor_id: actor&.id,
          action_type: action.to_s,
          target_type: target_type,
          target_id: target_id,
          changeset: changes,
          summary: summary,
          idempotency_key: key
        )
      rescue ActiveRecord::RecordNotUnique
        Loam::PendingAction.find_by!(idempotency_key: key)
      end

      private

      # A class stages a create (no target id yet); a record stages a change to
      # itself.
      def resolve_target(on)
        on.is_a?(Class) ? [ on.name, nil ] : [ on.class.name, on.id ]
      end

      # A KEYED (per-tenant HMAC), not a plain, digest of the proposal: a raw
      # SHA-256 of a low-entropy value (a tax id, an SSN) in an indexed column
      # would be a brute-force oracle from a DB dump. Reuses L-901's blind index.
      # Determinism relies on `changes` insertion order — the same caller yields
      # the same key; a reordered hash is treated as a different proposal.
      def compute_key(target_type, target_id, action, changes)
        payload = [ target_type, target_id, action, changes.to_json ].join("|")
        Loam::Encryption.blind_index_scoped(payload, "tenant/#{Loam.tenant!.id}")
      end
    end
  end
end
