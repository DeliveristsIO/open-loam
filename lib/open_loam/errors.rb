module OpenLoam
  class Error < StandardError; end

  # Raised whenever a tenant-scoped model is touched with no tenant in
  # OpenLoam::Current. This is a structural guardrail, not a convention: forgetting
  # the tenant context fails loudly (in tests, before it leaks) instead of
  # silently returning or writing cross-tenant data.
  class MissingTenantError < Error
    def initialize(msg = "No tenant set in OpenLoam::Current — wrap this call in OpenLoam.as_tenant(tenant) { ... }")
      super
    end
  end

  # Raised by admin controllers / callers when a policy check fails, and by a
  # OpenLoam::Workflow transition the current actor's role may not perform.
  class NotAuthorizedError < Error; end

  # Raised when a OpenLoam::Workflow transition is attempted from a state it does
  # not move from ("approve a report that was never submitted"). Like every
  # OpenLoam guardrail it fails at the call site rather than writing a state the
  # machine says is impossible.
  class InvalidTransitionError < Error; end

  # Raised when an event name does not follow the `domain.thing.happened` convention.
  class InvalidEventNameError < Error; end

  # Raised by OpenLoam::CustomFields#custom_field/#set_custom_field when the name
  # has no matching OpenLoam::FieldDefinition for this tenant + entity. Fails
  # loudly at the access site rather than silently reading/writing nil.
  class UnknownCustomFieldError < Error; end

  # Raised by require_feature! when a capability is turned OFF for the current
  # tenant. Distinct from NotAuthorizedError on purpose: a disabled feature is
  # "not here" (the capability does not exist for this tenant), not "you may
  # not" — so admin controllers render it as 404, not 403.
  class FeatureDisabledError < Error; end

  # Raised when a filter/sort is attempted on a custom field the current role may
  # not read (OpenLoam::CustomFieldIndex) — otherwise a filter would be an inference
  # oracle on a restricted field. A NotAuthorizedError so admin controllers render
  # it as 403, like any other field-access denial.
  class FieldAccessError < NotAuthorizedError; end

  # Raised when a controller action finishes without having authorized anything
  # (see the `verify_authorized!` guard in the generated base controllers).
  #
  # Deliberately NOT a NotAuthorizedError: that one means "this person may not",
  # and the base controllers render it as a tidy 403. This means "this code
  # forgot to ask", which is a developer bug that must not be dressed up as a
  # refusal — nothing rescues it, so it surfaces as a 500 in dev and a failure
  # in tests.
  class AuthorizationNotPerformedError < Error; end

  # Raised when a OpenLoam::BusinessRule with a `block_transition` action vetoes a
  # workflow transition. Distinct from NotAuthorizedError (a role gate) and
  # InvalidTransitionError (an illegal move): the move is legal and permitted,
  # but a rule says "not under these conditions".
  class TransitionVetoedError < Error; end
end
