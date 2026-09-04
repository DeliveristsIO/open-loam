require "open_loam/version"
require "open_loam/errors"
require "open_loam/current"
require "open_loam/events"
require "open_loam/policy"
require "open_loam/lifecycle"
require "open_loam/configs"
require "open_loam/features"
require "open_loam/auth_throttle"
require "open_loam/dictionaries"
require "open_loam/custom_field_index"
require "open_loam/undo"
require "open_loam/permissions"
require "open_loam/telemetry"
require "open_loam/eval"
require "open_loam/mcp"
require "open_loam/mcp/server"
require "open_loam/progress"
require "open_loam/cron"
require "open_loam/scheduler"
require "open_loam/csv"
require "open_loam/export"
require "open_loam/import"
require "open_loam/bulk"
require "open_loam/widgets"
require "open_loam/dashboard"
require "open_loam/overrides"
require "open_loam/open_api"
require "open_loam/encryption"
require "open_loam/base32"
require "open_loam/totp"
require "open_loam/pending_actions"
require "open_loam/perspectives"
require "open_loam/record_locks"
require "open_loam/event_stream"
require "open_loam/enrichers"
require "open_loam/search"
require "open_loam/search/driver"
require "open_loam/search/like_driver"
require "open_loam/search/token_driver"
require "open_loam/notifications"
require "open_loam/sso"
require "open_loam/business_rules"
require "open_loam/webhooks"
require "open_loam/inbound_webhooks"
require "open_loam/durable_events"
require "open_loam/engine" if defined?(Rails::Engine)

module OpenLoam
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

  # Feature-string permission check for the current actor's role (see
  # OpenLoam::Permissions) — deny-by-default, wildcard-aware. `role:` overrides the
  # actor's role. Returns false with no actor/role.
  def self.can?(permission, role: nil)
    role ||= Current.actor && OpenLoam::Membership.find_by(user_id: Current.actor.id)&.role
    OpenLoam::Permissions.allow?(role, permission)
  end

  # The approval-gate seam. When a caller runs under :confirm (an MCP tool acting
  # for an AI agent), a write should be STAGED for human approval via
  # OpenLoam::PendingActions.stage instead of committed. OpenLoam does not intercept
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
  require "open_loam/generated_key"
  require "open_loam/tenant_record"
  require "open_loam/auditable"
  require "open_loam/soft_deletable"
  require "open_loam/eventful"
  require "open_loam/custom_fields"
  require "open_loam/workflow"
  require "open_loam/searchable"
  require "open_loam/encryptable"
  require "open_loam/translatable"
  require "open_loam/commentable"
  require "open_loam/attachable"
end
