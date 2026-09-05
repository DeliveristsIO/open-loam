class AddDomainVerifiedAtToOpenLoamSsoProviders < ActiveRecord::Migration[8.2]
  def change
    add_column :open_loam_sso_providers, :domain_verified_at, :datetime
  end
end
