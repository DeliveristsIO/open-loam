require "test_helper"

# Structural guardrails. These are not feature tests — they enforce Loam's
# invariants on the codebase itself. If one of these fails, an agent (or a
# human) stepped outside the conventions.
class LoamGuardrailsTest < ActiveSupport::TestCase
  # Models that are legitimately not tenant-scoped.
  TENANCY_ALLOWLIST = %w[ApplicationRecord User Loam::Tenant].freeze

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
end
