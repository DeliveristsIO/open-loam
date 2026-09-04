module Loam
  # Links an external IdP identity (a provider's stable `sub`) to a local User.
  # The durable key SSO callbacks resolve on — an email can change at the IdP,
  # `sub` does not. Tenant-scoped (created and read inside the provider's tenant).
  class SsoIdentity < Loam::TenantRecord
    self.table_name = "loam_sso_identities"

    belongs_to :user
    belongs_to :sso_provider, class_name: "Loam::SsoProvider"

    validates :sub, presence: true, uniqueness: { scope: :sso_provider_id }
  end
end
