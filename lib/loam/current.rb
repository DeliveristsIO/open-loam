require "active_support/current_attributes"

module Loam
  # Per-request (and per-job) execution context. Every tenant-scoped query,
  # audit record, and published event reads from here.
  class Current < ActiveSupport::CurrentAttributes
    attribute :tenant, :actor
  end
end
