require "loam/version"
require "loam/errors"
require "loam/current"
require "loam/events"
require "loam/policy"
require "loam/lifecycle"
require "loam/notifications"
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
  require "loam/eventful"
  require "loam/custom_fields"
  require "loam/workflow"
end
