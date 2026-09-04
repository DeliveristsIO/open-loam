module Loam
  class Error < StandardError; end

  # Raised whenever a tenant-scoped model is touched with no tenant in
  # Loam::Current. This is a structural guardrail, not a convention: forgetting
  # the tenant context fails loudly (in tests, before it leaks) instead of
  # silently returning or writing cross-tenant data.
  class MissingTenantError < Error
    def initialize(msg = "No tenant set in Loam::Current — wrap this call in Loam.as_tenant(tenant) { ... }")
      super
    end
  end

  # Raised by admin controllers / callers when a policy check fails, and by a
  # Loam::Workflow transition the current actor's role may not perform.
  class NotAuthorizedError < Error; end

  # Raised when a Loam::Workflow transition is attempted from a state it does
  # not move from ("approve a report that was never submitted"). Like every
  # Loam guardrail it fails at the call site rather than writing a state the
  # machine says is impossible.
  class InvalidTransitionError < Error; end

  # Raised when an event name does not follow the `domain.thing.happened` convention.
  class InvalidEventNameError < Error; end

  # Raised by Loam::CustomFields#custom_field/#set_custom_field when the name
  # has no matching Loam::FieldDefinition for this tenant + entity. Fails
  # loudly at the access site rather than silently reading/writing nil.
  class UnknownCustomFieldError < Error; end

  # Raised by require_feature! when a capability is turned OFF for the current
  # tenant. Distinct from NotAuthorizedError on purpose: a disabled feature is
  # "not here" (the capability does not exist for this tenant), not "you may
  # not" — so admin controllers render it as 404, not 403.
  class FeatureDisabledError < Error; end

  # Raised when a filter/sort is attempted on a custom field the current role may
  # not read (Loam::CustomFieldIndex) — otherwise a filter would be an inference
  # oracle on a restricted field. A NotAuthorizedError so admin controllers render
  # it as 403, like any other field-access denial.
  class FieldAccessError < NotAuthorizedError; end

  # Raised when a Loam::BusinessRule with a `block_transition` action vetoes a
  # workflow transition. Distinct from NotAuthorizedError (a role gate) and
  # InvalidTransitionError (an illegal move): the move is legal and permitted,
  # but a rule says "not under these conditions".
  class TransitionVetoedError < Error; end
end
