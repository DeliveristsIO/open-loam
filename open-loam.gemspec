require_relative "lib/open_loam/version"

Gem::Specification.new do |spec|
  spec.name        = "open-loam"
  spec.version     = OpenLoam::VERSION
  spec.authors     = ["Grzegorz Smajdor"]
  spec.summary     = "AI-native Rails business foundation: tenancy, policies, audit, events, admin — decided, not re-litigated."
  spec.description = "OpenLoam pre-decides the 80% every business app shares (multi-tenancy, roles and field-level " \
                     "permissions, audit trails, a domain event bus, an admin surface) and ships the agent " \
                     "conventions (AGENTS.md, generators as the interface, structural guardrails) that make " \
                     "the codebase safe for AI agents to extend."
  # The docs site is the homepage; the repository is a separate link. Pointing
  # both at GitHub made RubyGems drop one of them and warn about it.
  spec.homepage    = "https://deliveristsio.github.io/open-loam/"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.2"

  repository = "https://github.com/DeliveristsIO/open-loam"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => repository,
    "changelog_uri" => "#{repository}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{repository}/issues",
    "rubygems_mfa_required" => "true"
  }

  # app/ is the engine's own code (OpenLoam::Tenant, Membership, AuditRecord,
  # FieldDefinition). Omitting it packages a gem that works from a path: source
  # and breaks the moment anyone installs the release.
  spec.files = Dir["{app,lib}/**/*", "LICENSE", "README.md", "CHANGELOG.md"]

  spec.add_dependency "rails", ">= 7.1"
  # `open_loam:install` generates a User with has_secure_password, so password
  # hashing is part of what OpenLoam guarantees rather than homework left to the
  # app. It must be a gem dependency, not a Gemfile line the generator writes:
  # apps bundle before they run the generator, so a Gemfile edit would arrive
  # too late to be installed.
  spec.add_dependency "bcrypt", "~> 3.1"
  # CSV import/export (OpenLoam::Import / OpenLoam::Export). `csv` left the default gems
  # in Ruby 3.4, so it must be declared or `require "csv"` fails at boot.
  spec.add_dependency "csv", "~> 3.3"
end
