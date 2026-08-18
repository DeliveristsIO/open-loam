require "rails/generators"
require "rails/generators/active_record"

module Loam
  module Generators
    # `rails g loam:install`
    #
    # Installs the Loam foundation into a host Rails app: tenants, memberships,
    # audit records, a minimal User, the admin surface, structural guardrail
    # tests, and AGENTS.md — the contract AI agents work against.
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def create_migrations
        migration_template "migrations/create_users.rb", "db/migrate/create_users.rb"
        migration_template "migrations/create_loam_tenants.rb", "db/migrate/create_loam_tenants.rb"
        migration_template "migrations/create_loam_memberships.rb", "db/migrate/create_loam_memberships.rb"
        migration_template "migrations/create_loam_audit_records.rb", "db/migrate/create_loam_audit_records.rb"
        migration_template "migrations/create_loam_field_definitions.rb", "db/migrate/create_loam_field_definitions.rb"
      end

      def create_user_model
        template "user.rb", "app/models/user.rb"
      end

      def create_initializer
        template "initializer.rb", "config/initializers/loam.rb"
      end

      def create_agents_md
        template "AGENTS.md", "AGENTS.md"
      end

      def create_admin
        template "admin/base_controller.rb", "app/controllers/admin/base_controller.rb"
        template "admin/sessions_controller.rb", "app/controllers/admin/sessions_controller.rb"
        template "admin/dashboard_controller.rb", "app/controllers/admin/dashboard_controller.rb"
        template "admin/field_definitions_controller.rb", "app/controllers/admin/field_definitions_controller.rb"
        template "admin/layout.html.erb", "app/views/layouts/admin.html.erb"
        template "admin/sessions_new.html.erb", "app/views/admin/sessions/new.html.erb"
        template "admin/dashboard_index.html.erb", "app/views/admin/dashboard/index.html.erb"
        template "admin/field_definitions_index.html.erb", "app/views/admin/field_definitions/index.html.erb"
        template "admin/field_definitions_new.html.erb", "app/views/admin/field_definitions/new.html.erb"
      end

      def add_routes
        route <<~RUBY
          namespace :admin do
            root "dashboard#index"
            resource :session, only: %i[new create destroy]
            resources :field_definitions, only: %i[index new create destroy]
          end
        RUBY
      end

      def create_guardrail_tests
        template "guardrails_test.rb", "test/loam_guardrails_test.rb"
      end

      # An app generated with --skip-test has no test/test_helper.rb. Creating
      # one here would be Loam deciding how the app tests; saying so and moving
      # on leaves the install complete either way.
      def wire_test_helpers
        unless File.file?(File.join(destination_root, "test/test_helper.rb"))
          say ""
          say "No test/test_helper.rb (--skip-test?) — skipping Loam test wiring.", :yellow
          say "  test/loam_guardrails_test.rb was still written. To run it, add to your test setup:"
          say "    require \"loam/test_helpers\"   (after the environment is loaded)"
          say "    include Loam::TestHelpers       (in your base test case)"
          return
        end

        inject_into_file "test/test_helper.rb", "require \"loam/test_helpers\"\n",
                         after: /require_relative "\.\.\/config\/environment"\n/
        inject_into_file "test/test_helper.rb", "    include Loam::TestHelpers\n",
                         after: /class TestCase\n/
      end

      def print_next_steps
        say ""
        say "Loam installed. Next:", :green
        say "  1. bin/rails db:migrate"
        say "  2. rails g loam:entity Equipment name:string daily_rate:decimal status:string --domain rental"
        say "  3. Read AGENTS.md before pointing an AI agent at this app."
      end
    end
  end
end
