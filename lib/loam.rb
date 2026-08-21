require "loam/version"
require "loam/errors"
require "loam/current"
require "loam/events"
require "loam/policy"
require "loam/lifecycle"
require "loam/configs"
require "loam/features"
require "loam/dictionaries"
require "loam/progress"
require "loam/encryption"
require "loam/base32"
require "loam/totp"
require "loam/pending_actions"
require "loam/perspectives"
require "loam/record_locks"
require "loam/event_stream"
require "loam/enrichers"
require "loam/search"
require "loam/search/driver"
require "loam/search/like_driver"
require "loam/search/token_driver"
require "loam/notifications"
require "loam/sso"
require "loam/business_rules"
require "loam/webhooks"
require "loam/engine" if defined?(Rails::Engine)

module Loam
  # The current tenant, or a loud failure. This is THE guardrail: tenant-scoped
  # code paths call this, so a missing tenant context can never silently widen
  # a query to all tenants.
  def self.tenant!
    Current.tenant or raise MissingTenantError
  end

  def self.tenant
    Current.tenant
  end

  def self.actor
    Current.actor
  end

  # The approval-gate seam. When a caller runs under :confirm (an MCP tool acting
  # for an AI agent), a write should be STAGED for human approval via
  # Loam::PendingActions.stage instead of committed. Loam does not intercept
  # Active Record globally — this is the documented hook a write path checks.
  def self.mutation_mode
    Current.mutation_mode || :direct
  end

  def self.require_confirmation?
    mutation_mode == :confirm
  end

  # Run a block with writes gated for approval. The one blessed way to enter
  # confirm-mode; restores the previous mode afterwards.
  def self.with_confirmation
    previous = Current.mutation_mode
    Current.mutation_mode = :confirm
    yield
  ensure
    Current.mutation_mode = previous
  end

  # Run a block inside a tenant (and optional actor) context, restoring the
  # previous context afterwards. The one blessed way to switch tenants.
  def self.as_tenant(tenant, actor: nil)
    previous_tenant = Current.tenant
    previous_actor = Current.actor
    Current.tenant = tenant
    Current.actor = actor if actor
    yield
  ensure
    Current.tenant = previous_tenant
    Current.actor = previous_actor
  end
end

ActiveSupport.on_load(:active_record) do
  require "loam/tenant_record"
  require "loam/auditable"
  require "loam/soft_deletable"
  require "loam/eventful"
  require "loam/custom_fields"
  require "loam/workflow"
  require "loam/searchable"
  require "loam/encryptable"
  require "loam/commentable"
  require "loam/attachable"
end
