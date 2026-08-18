module Loam
  # Tenant lifecycle: what a brand-new tenant gets for free.
  #
  # An app declares seeding once, in config/initializers/loam.rb:
  #
  #   Loam.on_tenant_created do |tenant|
  #     Loam::FieldDefinition.find_or_create_by!(entity_type: "Equipment", name: "asset_tag") { ... }
  #   end
  #
  # The block runs inside `Loam.as_tenant(tenant)`, so tenant-scoped writes
  # need no extra ceremony.
  #
  # THE CONTRACT: callbacks MUST be idempotent. They fire once when a tenant is
  # created, and again for EVERY existing tenant whenever `bin/rails loam:sync`
  # runs — which is how a role/field/default added by a later release reaches
  # tenants that already exist. Write `find_or_create_by!`, never `create!`.
  module Lifecycle
    # Registered blocks, in declaration order. Registration returns the block
    # itself so a caller (typically a test) can deregister it again.
    def self.tenant_created_callbacks
      @tenant_created_callbacks ||= []
    end

    def self.on_tenant_created(&block)
      tenant_created_callbacks << block
      block
    end

    # The single execution path for a tenant's callbacks — used both by
    # Loam::Tenant's after_create_commit and by sync_tenants!, so "runs inside
    # as_tenant, in declaration order" can never drift between the two.
    #
    # Exceptions propagate: a failing callback fails the tenant creation (Rails
    # re-raises from after_commit) or the sync run, loudly, like every other
    # Loam guardrail.
    def self.run_tenant_created(tenant)
      Loam.as_tenant(tenant) do
        tenant_created_callbacks.each { |callback| callback.call(tenant) }
      end
    end

    # Re-runs every on_tenant_created callback for every existing tenant.
    # Idempotent by contract (see above) — safe to run on every deploy.
    # Returns the number of tenants synced.
    def self.sync_tenants!
      count = 0
      Loam::Tenant.find_each do |tenant|
        run_tenant_created(tenant)
        count += 1
      end
      count
    end

    # Role names this app expects every tenant to have — declared in the
    # initializer (`Loam.default_roles = %w[manager employee]`) and read by
    # whatever seeds memberships. A registry, not a mechanism: Loam does not
    # create roles for you, because who gets which role is business logic.
    def self.default_roles
      @default_roles ||= []
    end

    def self.default_roles=(roles)
      @default_roles = Array(roles).map(&:to_s)
    end
  end

  # The public surface is on Loam itself — apps and agents write
  # `Loam.on_tenant_created`, never `Loam::Lifecycle.on_tenant_created`.
  def self.on_tenant_created(&block) = Lifecycle.on_tenant_created(&block)
  def self.tenant_created_callbacks = Lifecycle.tenant_created_callbacks
  def self.sync_tenants! = Lifecycle.sync_tenants!
  def self.default_roles = Lifecycle.default_roles
  def self.default_roles=(roles)
    Lifecycle.default_roles = roles
  end
end
