require "active_support/current_attributes"

module Loam
  # Per-request (and per-job) execution context. Every tenant-scoped query,
  # audit record, and published event reads from here.
  class Current < ActiveSupport::CurrentAttributes
    # config_cache memoizes resolved Loam::Configs values for the duration of
    # one request/job, keyed by [key, tenant_id]. It resets with everything else
    # here, so a value can never be read stale across requests.
    attribute :tenant, :actor, :config_cache
  end
end
