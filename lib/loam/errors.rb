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

  # Raised by admin controllers / callers when a policy check fails.
  class NotAuthorizedError < Error; end

  # Raised when an event name does not follow the `domain.thing.happened` convention.
  class InvalidEventNameError < Error; end

  # Raised by Loam::CustomFields#custom_field/#set_custom_field when the name
  # has no matching Loam::FieldDefinition for this tenant + entity. Fails
  # loudly at the access site rather than silently reading/writing nil.
  class UnknownCustomFieldError < Error; end
end
