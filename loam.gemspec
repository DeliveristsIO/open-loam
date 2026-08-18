require_relative "lib/loam/version"

Gem::Specification.new do |spec|
  spec.name        = "loam"
  spec.version     = Loam::VERSION
  spec.authors     = ["Loam"]
  spec.summary     = "AI-native Rails business foundation: tenancy, policies, audit, events, admin — decided, not re-litigated."
  spec.description = "Loam pre-decides the 80% every business app shares (multi-tenancy, roles and field-level " \
                     "permissions, audit trails, a domain event bus, an admin surface) and ships the agent " \
                     "conventions (AGENTS.md, generators as the interface, structural guardrails) that make " \
                     "the codebase safe for AI agents to extend."
  spec.homepage    = "https://github.com/DeliveristsIO/loam"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*", "LICENSE", "README.md"]

  spec.add_dependency "rails", ">= 7.1"
end
