module Loam
  # The tenant itself is deliberately NOT tenant-scoped — it is the axis the
  # rest of the system is scoped by.
  class Tenant < ActiveRecord::Base
    self.table_name = "loam_tenants"

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true

    has_many :memberships, class_name: "Loam::Membership", dependent: :delete_all

    # A new tenant is never empty: whatever the app registered via
    # Loam.on_tenant_created runs here, inside this tenant's context. After
    # commit, so callbacks see a persisted tenant and may enqueue jobs.
    # `bin/rails loam:sync` re-runs the same callbacks for existing tenants —
    # which is why they must be idempotent (see Loam::Lifecycle).
    after_create_commit { Loam::Lifecycle.run_tenant_created(self) }
  end
end
