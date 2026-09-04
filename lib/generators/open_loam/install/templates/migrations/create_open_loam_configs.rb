class CreateOpenLoamConfigs < ActiveRecord::Migration[<%= ActiveRecord::VERSION::STRING.to_f %>]
  def change
    create_table :open_loam_configs<%= open_loam_id_option %> do |t|
      t.string :key, null: false
      # Nullable: a NULL tenant_id is the GLOBAL row; a set one is a per-tenant
      # override. So this is NOT a tenant-scoped table.
      t.references :tenant, null: true, foreign_key: { to_table: :open_loam_tenants }<%= open_loam_type_option %>
      # Any JSON-able value under one key. Nullable on purpose: row existence is
      # the "is it set" signal, and JSON null is itself a storable value.
      t.json :value_json
      t.timestamps
    end

    # One global row per key (partial: only where there is no tenant).
    add_index :open_loam_configs, :key, unique: true, where: "tenant_id IS NULL",
              name: "index_loam_configs_global_key"
    # One override row per key per tenant.
    add_index :open_loam_configs, %i[key tenant_id], unique: true,
              name: "index_loam_configs_on_key_and_tenant"
  end
end
