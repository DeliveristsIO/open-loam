module OpenLoam
  # The tenant itself is deliberately NOT tenant-scoped — it is the axis the
  # rest of the system is scoped by.
  class Tenant < ActiveRecord::Base
    include OpenLoam::GeneratedKey
    self.table_name = "open_loam_tenants"

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true

    has_many :memberships, class_name: "OpenLoam::Membership", dependent: :delete_all

    # A new tenant is never empty: whatever the app registered via
    # OpenLoam.on_tenant_created runs here, inside this tenant's context. After
    # commit, so callbacks see a persisted tenant and may enqueue jobs.
    # `bin/rails open_loam:sync` re-runs the same callbacks for existing tenants —
    # which is why they must be idempotent (see OpenLoam::Lifecycle).
    after_create_commit { OpenLoam::Lifecycle.run_tenant_created(self) }
  end
end
