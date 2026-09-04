class CreateOpenLoamSsoProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :open_loam_sso_providers do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }
      t.string :name, null: false
      t.string :protocol, null: false, default: "oidc"  # "oidc" shipped; "saml" is a seam
      t.string :issuer                                    # OIDC discovery base (.well-known)
      t.string :client_id
      t.text :client_secret                               # ENCRYPTED at rest (tenant-scoped key)
      t.string :domain, null: false                       # email domain for home-realm discovery
      t.string :jit_role, null: false, default: "employee"  # role for JIT-provisioned users
      t.json :group_role_map, null: false, default: {}    # IdP group -> OpenLoam role (first match wins)
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    # HRD resolves a provider by email domain, cross-tenant, before login — so the
    # domain is globally unique (one owning IdP per domain).
    add_index :open_loam_sso_providers, :domain, unique: true
    add_index :open_loam_sso_providers, %i[tenant_id active]

    # The durable link between an external identity (provider + subject) and a
    # local User — the primary lookup on callback (email can change at the IdP,
    # `sub` does not).
    create_table :open_loam_sso_identities do |t|
      t.references :tenant, null: false, foreign_key: { to_table: :open_loam_tenants }
      t.references :sso_provider, null: false, foreign_key: { to_table: :open_loam_sso_providers }
      t.bigint :user_id, null: false
      t.string :sub, null: false  # the IdP's stable subject identifier
      t.timestamps
    end
    add_index :open_loam_sso_identities, %i[sso_provider_id sub], unique: true
    add_index :open_loam_sso_identities, :user_id
  end
end
