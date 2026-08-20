require "active_support/current_attributes"

module Loam
  # Per-request (and per-job) execution context. Every tenant-scoped query,
  # audit record, and published event reads from here.
  class Current < ActiveSupport::CurrentAttributes
    # config_cache memoizes resolved Loam::Configs values for the duration of
    # one request/job, keyed by [key, tenant_id]. It resets with everything else
    # here, so a value can never be read stale across requests.
    #
    # mutation_mode is the approval-gate seam (Loam::PendingActions): nil/:direct
    # means writes commit normally; :confirm means a caller (an MCP tool acting
    # for an AI agent) stages writes for human approval instead. It lives here so
    # it is per-request and resets automatically.
    attribute :tenant, :actor, :config_cache, :mutation_mode
  end
end
