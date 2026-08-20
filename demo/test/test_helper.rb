ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "loam/test_helpers"
require "rails/test_help"

# Minting 10 BCrypt-hashed recovery codes at the default cost adds seconds to
# every MFA enrollment; MIN_COST keeps the suite fast (standard Rails practice —
# never do this outside tests).
require "bcrypt"
BCrypt::Engine.cost = BCrypt::Engine::MIN_COST

module ActiveSupport
  class TestCase
    include Loam::TestHelpers
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
