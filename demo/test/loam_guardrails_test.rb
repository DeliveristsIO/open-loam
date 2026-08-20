require "test_helper"

# Structural guardrails. These are not feature tests — they enforce Loam's
# invariants on the codebase itself. If one of these fails, an agent (or a
# human) stepped outside the conventions.
class LoamGuardrailsTest < ActiveSupport::TestCase
  # Models that are legitimately not tenant-scoped. Loam::Config holds both
  # global (tenant_id NULL) and per-tenant override rows, so tenancy is a
  # nullable column and resolution lives in vetted gem code (Loam::Configs).
  # Loam::MfaCredential belongs to the person, who spans tenants — MFA is
  # verified at login before any tenant is chosen.
  TENANCY_ALLOWLIST = %w[ApplicationRecord User Loam::Tenant Loam::Config Loam::MfaCredential].freeze

  # Rails' own engine models (storage, rich text, jobs) are framework
  # plumbing, not business data — they are out of scope for tenant linting.
  FRAMEWORK_NAMESPACES = %w[ActiveStorage:: ActionText:: ActionMailbox:: SolidQueue:: SolidCache:: SolidCable::].freeze

  test "every app model is tenant-scoped (inherits Loam::TenantRecord)" do
    Rails.application.eager_load!

    offenders = ActiveRecord::Base.descendants.reject do |model|
      model.abstract_class? ||
        model.name.nil? ||
        TENANCY_ALLOWLIST.include?(model.name) ||
        FRAMEWORK_NAMESPACES.any? { |ns| model.name.start_with?(ns) } ||
        model <= Loam::TenantRecord
    end

    assert_empty offenders,
      "These models are NOT tenant-scoped: #{offenders.map(&:name).join(', ')}. " \
      "Business models must inherit Loam::TenantRecord (use `rails g loam:entity`). " \
      "If a model is intentionally global, add it to TENANCY_ALLOWLIST here — in review, on purpose."
  end

  test "touching a tenant-scoped model with no tenant context raises" do
    Loam::Current.reset

    assert_raises(Loam::MissingTenantError) { Loam::AuditRecord.count }
    assert_raises(Loam::MissingTenantError) { Loam::Membership.first }
  end

  test "nobody uses .unscoped outside vetted framework code" do
    offenders = Dir[Rails.root.join("app/**/*.rb")].select do |file|
      File.read(file).match?(/\bunscoped\b/)
    end

    assert_empty offenders,
      ".unscoped found in: #{offenders.join(', ')}. It bypasses tenant isolation — remove it."
  end

  # Agent harnesses read AGENTS.md into a context window and truncate what
  # doesn't fit — silently. An overweight file doesn't warn, it just loses its
  # tail, and the tail is where the invariants live.
  AGENTS_MD_BUDGET_BYTES = 32_768

  test "AGENTS.md stays inside its byte budget" do
    path = Rails.root.join("AGENTS.md")

    assert path.exist?, "AGENTS.md is missing from #{Rails.root} — it is the contract AI agents work against."
    assert path.size <= AGENTS_MD_BUDGET_BYTES,
      "AGENTS.md is #{path.size} bytes, over the #{AGENTS_MD_BUDGET_BYTES}-byte budget. " \
      "Agent harnesses truncate instruction files without warning, so the tail — invariants, " \
      "definition of done — would silently stop being read. Cut prose or move detail into " \
      "docs/ and link it, rather than raising the budget."
  end

  test "every Loam::FieldDefinition entity_type resolves to a class that uses Loam::CustomFields" do
    Rails.application.eager_load!

    offenders = Loam::FieldDefinition.unscoped.distinct.pluck(:entity_type).reject do |entity_type|
      klass = entity_type.safe_constantize
      klass && klass.include?(Loam::CustomFields)
    end

    assert_empty offenders,
      "These Loam::FieldDefinition entity_type values don't resolve to a class that " \
      "`include Loam::CustomFields`: #{offenders.join(', ')}. Likely a typo when the field was created."
  end
end
