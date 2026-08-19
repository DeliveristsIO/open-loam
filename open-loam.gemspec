require_relative "lib/loam/version"

Gem::Specification.new do |spec|
  spec.name        = "open-loam"
  spec.version     = Loam::VERSION
  spec.authors     = ["Grzegorz Smajdor"]
  spec.summary     = "AI-native Rails business foundation: tenancy, policies, audit, events, admin — decided, not re-litigated."
  spec.description = "Loam pre-decides the 80% every business app shares (multi-tenancy, roles and field-level " \
                     "permissions, audit trails, a domain event bus, an admin surface) and ships the agent " \
                     "conventions (AGENTS.md, generators as the interface, structural guardrails) that make " \
                     "the codebase safe for AI agents to extend."
  spec.homepage    = "https://github.com/DeliveristsIO/loam"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/releases",
    "rubygems_mfa_required" => "true"
  }

  # app/ is the engine's own code (Loam::Tenant, Membership, AuditRecord,
  # FieldDefinition). Omitting it packages a gem that works from a path: source
  # and breaks the moment anyone installs the release.
  spec.files = Dir["{app,lib}/**/*", "LICENSE", "README.md"]

  spec.add_dependency "rails", ">= 7.1"
  # `loam:install` generates a User with has_secure_password, so password
  # hashing is part of what Loam guarantees rather than homework left to the
  # app. It must be a gem dependency, not a Gemfile line the generator writes:
  # apps bundle before they run the generator, so a Gemfile edit would arrive
  # too late to be installed.
  spec.add_dependency "bcrypt", "~> 3.1"
end
