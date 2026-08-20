module Loam
  # A single configuration setting: one namespaced key, one JSON-able value.
  #
  # Deliberately NOT a Loam::TenantRecord. A setting exists at two levels — a
  # GLOBAL default (tenant_id NULL) that every tenant sees, and a per-tenant
  # OVERRIDE (tenant_id set) that wins for that one tenant — so tenancy is a
  # nullable column here, not a default_scope. Resolving a key means reading
  # across both levels at once, which is why the lookup lives in vetted gem code
  # (Loam::Configs), never in app code (see the tenancy allowlist in
  # test/loam_guardrails_test.rb).
  #
  # The value goes in a json column, so a bool, number, string, array, or hash
  # all round-trip under the same key. Row existence — not the value — is what
  # marks a key as set, so the value may legitimately be JSON null.
  class Config < ApplicationRecord
    self.table_name = "loam_configs"

    belongs_to :tenant, class_name: "Loam::Tenant", optional: true

    validates :key, presence: true
    # One global per key, one override per key per tenant. AR renders the nil
    # scope as `tenant_id IS NULL`, so this covers both cases; the two partial
    # indexes in the migration are the race-proof guarantee behind it.
    validates :key, uniqueness: { scope: :tenant_id }
  end
end
