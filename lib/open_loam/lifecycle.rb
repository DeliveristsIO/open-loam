module OpenLoam
  # Tenant lifecycle: what a brand-new tenant gets for free.
  #
  # An app declares seeding once, in config/initializers/open_loam.rb:
  #
  #   OpenLoam.on_tenant_created do |tenant|
  #     OpenLoam::FieldDefinition.find_or_create_by!(entity_type: "Equipment", name: "asset_tag") { ... }
  #   end
  #
  # The block runs inside `OpenLoam.as_tenant(tenant)`, so tenant-scoped writes
  # need no extra ceremony.
  #
  # THE CONTRACT: callbacks MUST be idempotent. They fire once when a tenant is
  # created, and again for EVERY existing tenant whenever `bin/rails open_loam:sync`
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
    # OpenLoam::Tenant's after_create_commit and by sync_tenants!, so "runs inside
    # as_tenant, in declaration order" can never drift between the two.
    #
    # Exceptions propagate: a failing callback fails the tenant creation (Rails
    # re-raises from after_commit) or the sync run, loudly, like every other
    # OpenLoam guardrail.
    def self.run_tenant_created(tenant)
      OpenLoam.as_tenant(tenant) do
        tenant_created_callbacks.each { |callback| callback.call(tenant) }
      end
    end

    # Re-runs every on_tenant_created callback for every existing tenant.
    # Idempotent by contract (see above) — safe to run on every deploy.
    # Returns the number of tenants synced.
    def self.sync_tenants!
      count = 0
      OpenLoam::Tenant.find_each do |tenant|
        run_tenant_created(tenant)
        count += 1
      end
      count
    end

    # Role names this app expects every tenant to have — declared in the
    # initializer (`OpenLoam.default_roles = %w[manager employee]`) and read by
    # whatever seeds memberships. A registry, not a mechanism: OpenLoam does not
    # create roles for you, because who gets which role is business logic.
    def self.default_roles
      @default_roles ||= []
    end

    def self.default_roles=(roles)
      @default_roles = Array(roles).map(&:to_s)
    end

    # App-wide setting defaults: `{ "billing.currency" => "USD" }`, declared in
    # the initializer and read by OpenLoam::Configs as the baseline a key resolves
    # to when no global row and no tenant override exist. A registry, like
    # default_roles — declaring a default here needs no migration and no row.
    def self.config_defaults
      @config_defaults ||= {}
    end

    def self.config_defaults=(defaults)
      @config_defaults = defaults.to_h.transform_keys(&:to_s)
    end

    # Event-name patterns (OpenLoam::Events.pattern_matches?) whose events may be
    # pushed to the browser over SSE (OpenLoam::EventStream). DEFAULT OFF — an empty
    # list means nothing reaches a browser; an app opts in explicitly, so a stray
    # event never leaks by default.
    def self.broadcast_events
      @broadcast_events ||= []
    end

    def self.broadcast_events=(patterns)
      @broadcast_events = Array(patterns).map(&:to_s)
    end

    # Event-name patterns EXCLUDED from the event log (OpenLoam::EventLog).
    # Capture is on by default and there is no match-all pattern to opt into, so
    # this exclusion list is the only knob: empty captures everything.
    #
    # The default excludes progress ticks, which fire once per processed row
    # during a bulk import — high volume, no history worth keeping, and each one
    # would otherwise be an inline INSERT in the import's own thread.
    def self.uncaptured_events
      @uncaptured_events ||= [ "open_loam.progress." ]
    end

    def self.uncaptured_events=(patterns)
      @uncaptured_events = Array(patterns).map(&:to_s)
    end

    # How long a captured event is kept before OpenLoam::EventLogPruneJob deletes
    # it. nil disables pruning — an unbounded log, which is a deliberate choice
    # an app has to make, not the default.
    def self.event_log_retention
      defined?(@event_log_retention) ? @event_log_retention : 90.days
    end

    def self.event_log_retention=(duration)
      @event_log_retention = duration
    end

    # The locales content translations (OpenLoam::Translatable) may be authored in —
    # declared in the initializer (`OpenLoam.locales = %w[en de pl]`), so the admin
    # knows which languages to offer. A registry like the others; defaults to the
    # single default locale.
    def self.locales
      @locales ||= [ default_locale ]
    end

    def self.locales=(codes)
      @locales = Array(codes).map(&:to_s)
    end

    # Job classes an app EXPLICITLY allows the scheduler to run, beyond the ones
    # it registers via OpenLoam::Scheduler.register. An allowlist (not "any
    # ActiveJob") so a tenant admin can't schedule ActiveStorage::PurgeJob or a
    # mailer. Declared in the initializer: `OpenLoam.schedulable_jobs = %w[DigestJob]`.
    def self.schedulable_jobs
      @schedulable_jobs ||= []
    end

    def self.schedulable_jobs=(names)
      @schedulable_jobs = Array(names).map(&:to_s)
    end

    def self.default_locale
      (defined?(I18n) ? I18n.default_locale : :en).to_s
    end

    # The current request/job locale — content reads overlay onto it. Request
    # state like the tenant (set in a before_action, reset with OpenLoam::Current).
    def self.locale
      (OpenLoam::Current.locale || default_locale).to_s
    end

    def self.locale=(code)
      OpenLoam::Current.locale = code&.to_s
    end

    # Known feature flags: `{ "beta_dashboard" => { default: false, description:
    # "..." } }`, declared in the initializer and read by OpenLoam::Features. A
    # registry like the others — a flag with no row resolves to its declared
    # default, and the admin can list EVERY known flag, not just toggled ones.
    def self.feature_defaults
      @feature_defaults ||= {}
    end

    # Normalizes both levels: outer keys to strings, and each flag's own hash to
    # symbol keys, so `{ "x" => { "default" => true } }` and
    # `{ x: { default: true } }` behave identically.
    def self.feature_defaults=(defaults)
      @feature_defaults = defaults.to_h.each_with_object({}) do |(name, spec), out|
        out[name.to_s] = spec.to_h.transform_keys(&:to_sym)
      end
    end
  end

  # The public surface is on OpenLoam itself — apps and agents write
  # `OpenLoam.on_tenant_created`, never `OpenLoam::Lifecycle.on_tenant_created`.
  def self.on_tenant_created(&block) = Lifecycle.on_tenant_created(&block)
  def self.tenant_created_callbacks = Lifecycle.tenant_created_callbacks
  def self.sync_tenants! = Lifecycle.sync_tenants!
  def self.default_roles = Lifecycle.default_roles
  def self.default_roles=(roles)
    Lifecycle.default_roles = roles
  end
  def self.config_defaults = Lifecycle.config_defaults
  def self.config_defaults=(defaults)
    Lifecycle.config_defaults = defaults
  end
  def self.feature_defaults = Lifecycle.feature_defaults
  def self.feature_defaults=(defaults)
    Lifecycle.feature_defaults = defaults
  end
  def self.broadcast_events = Lifecycle.broadcast_events
  def self.broadcast_events=(patterns)
    Lifecycle.broadcast_events = patterns
  end
  def self.uncaptured_events = Lifecycle.uncaptured_events
  def self.uncaptured_events=(patterns)
    Lifecycle.uncaptured_events = patterns
  end
  def self.event_log_retention = Lifecycle.event_log_retention
  def self.event_log_retention=(duration)
    Lifecycle.event_log_retention = duration
  end
  def self.locales = Lifecycle.locales
  def self.locales=(codes)
    Lifecycle.locales = codes
  end
  def self.schedulable_jobs = Lifecycle.schedulable_jobs
  def self.schedulable_jobs=(names)
    Lifecycle.schedulable_jobs = names
  end
  def self.default_locale = Lifecycle.default_locale
  def self.locale = Lifecycle.locale
  def self.locale=(code)
    Lifecycle.locale = code
  end
end
