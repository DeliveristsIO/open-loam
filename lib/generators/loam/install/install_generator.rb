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
        migration_template "migrations/create_loam_notifications.rb", "db/migrate/create_loam_notifications.rb"
        migration_template "migrations/create_loam_api_tokens.rb", "db/migrate/create_loam_api_tokens.rb"
        migration_template "migrations/create_loam_webhook_endpoints.rb", "db/migrate/create_loam_webhook_endpoints.rb"
        migration_template "migrations/create_loam_comments.rb", "db/migrate/create_loam_comments.rb"
        migration_template "migrations/create_loam_configs.rb", "db/migrate/create_loam_configs.rb"
        migration_template "migrations/create_loam_mfa_credentials.rb", "db/migrate/create_loam_mfa_credentials.rb"
        migration_template "migrations/create_loam_pending_actions.rb", "db/migrate/create_loam_pending_actions.rb"
        migration_template "migrations/create_loam_perspectives.rb", "db/migrate/create_loam_perspectives.rb"
        migration_template "migrations/create_loam_record_locks.rb", "db/migrate/create_loam_record_locks.rb"
        migration_template "migrations/create_loam_business_rules.rb", "db/migrate/create_loam_business_rules.rb"
        migration_template "migrations/create_loam_search_tokens.rb", "db/migrate/create_loam_search_tokens.rb"
        migration_template "migrations/create_loam_sso_providers.rb", "db/migrate/create_loam_sso_providers.rb"
        migration_template "migrations/create_loam_dictionaries.rb", "db/migrate/create_loam_dictionaries.rb"
        migration_template "migrations/create_loam_dictionary_entries.rb", "db/migrate/create_loam_dictionary_entries.rb"
        migration_template "migrations/create_loam_progress_jobs.rb", "db/migrate/create_loam_progress_jobs.rb"
        migration_template "migrations/create_loam_scheduled_jobs.rb", "db/migrate/create_loam_scheduled_jobs.rb"
      end

      # Attachments (Loam::Attachable, included in every generated entity) are
      # ActiveStorage, which needs its own tables. The task copies its
      # migration and says so if it is already there, so running it twice is
      # harmless.
      def install_active_storage
        unless defined?(ActiveStorage::Engine)
          say ""
          say "ActiveStorage is not available in this app — attachments will not work.", :yellow
          say "  Generated entities `include Loam::Attachable`; either re-create the app without"
          say "  --skip-active-storage, or remove that include from app/models."
          return
        end

        rails_command "active_storage:install"
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
        template "admin/mfa_controller.rb", "app/controllers/admin/mfa_controller.rb"
        template "admin/sudo_controller.rb", "app/controllers/admin/sudo_controller.rb"
        template "admin/pending_actions_controller.rb", "app/controllers/admin/pending_actions_controller.rb"
        template "admin/perspectives_controller.rb", "app/controllers/admin/perspectives_controller.rb"
        template "admin/record_locks_controller.rb", "app/controllers/admin/record_locks_controller.rb"
        template "admin/events_controller.rb", "app/controllers/admin/events_controller.rb"
        template "admin/dashboard_controller.rb", "app/controllers/admin/dashboard_controller.rb"
        template "admin/field_definitions_controller.rb", "app/controllers/admin/field_definitions_controller.rb"
        template "admin/notifications_controller.rb", "app/controllers/admin/notifications_controller.rb"
        template "admin/webhook_endpoints_controller.rb", "app/controllers/admin/webhook_endpoints_controller.rb"
        template "admin/api_tokens_controller.rb", "app/controllers/admin/api_tokens_controller.rb"
        template "admin/comments_controller.rb", "app/controllers/admin/comments_controller.rb"
        template "admin/configs_controller.rb", "app/controllers/admin/configs_controller.rb"
        template "admin/features_controller.rb", "app/controllers/admin/features_controller.rb"
        template "admin/business_rules_controller.rb", "app/controllers/admin/business_rules_controller.rb"
        template "admin/sso_providers_controller.rb", "app/controllers/admin/sso_providers_controller.rb"
        template "admin/dictionaries_controller.rb", "app/controllers/admin/dictionaries_controller.rb"
        template "admin/dictionary_entries_controller.rb", "app/controllers/admin/dictionary_entries_controller.rb"
        template "admin/progress_jobs_controller.rb", "app/controllers/admin/progress_jobs_controller.rb"
        template "admin/scheduled_jobs_controller.rb", "app/controllers/admin/scheduled_jobs_controller.rb"
        template "admin/search_controller.rb", "app/controllers/admin/search_controller.rb"
        template "admin/pagination.rb", "app/controllers/admin/pagination.rb"
        template "admin/layout.html.erb", "app/views/layouts/admin.html.erb"
        template "admin/sessions_new.html.erb", "app/views/admin/sessions/new.html.erb"
        template "admin/sessions_mfa_challenge.html.erb", "app/views/admin/sessions/mfa_challenge.html.erb"
        template "admin/mfa_show.html.erb", "app/views/admin/mfa/show.html.erb"
        template "admin/mfa_new.html.erb", "app/views/admin/mfa/new.html.erb"
        template "admin/mfa_activated.html.erb", "app/views/admin/mfa/activated.html.erb"
        template "admin/sudo_new.html.erb", "app/views/admin/sudo/new.html.erb"
        template "admin/pending_actions_index.html.erb", "app/views/admin/pending_actions/index.html.erb"
        template "admin/perspectives_index.html.erb", "app/views/admin/perspectives/index.html.erb"
        template "admin/dashboard_index.html.erb", "app/views/admin/dashboard/index.html.erb"
        template "admin/field_definitions_index.html.erb", "app/views/admin/field_definitions/index.html.erb"
        template "admin/field_definitions_new.html.erb", "app/views/admin/field_definitions/new.html.erb"
        template "admin/notifications_index.html.erb", "app/views/admin/notifications/index.html.erb"
        template "admin/webhook_endpoints_index.html.erb", "app/views/admin/webhook_endpoints/index.html.erb"
        template "admin/webhook_endpoints_new.html.erb", "app/views/admin/webhook_endpoints/new.html.erb"
        template "admin/api_tokens_index.html.erb", "app/views/admin/api_tokens/index.html.erb"
        template "admin/configs_index.html.erb", "app/views/admin/configs/index.html.erb"
        template "admin/configs_edit.html.erb", "app/views/admin/configs/edit.html.erb"
        template "admin/features_index.html.erb", "app/views/admin/features/index.html.erb"
        template "admin/business_rules_index.html.erb", "app/views/admin/business_rules/index.html.erb"
        template "admin/business_rules_new.html.erb", "app/views/admin/business_rules/new.html.erb"
        template "admin/business_rules_edit.html.erb", "app/views/admin/business_rules/edit.html.erb"
        template "admin/business_rules_form.html.erb", "app/views/admin/business_rules/_form.html.erb"
        template "admin/sso_providers_index.html.erb", "app/views/admin/sso_providers/index.html.erb"
        template "admin/sso_providers_new.html.erb", "app/views/admin/sso_providers/new.html.erb"
        template "admin/sso_providers_edit.html.erb", "app/views/admin/sso_providers/edit.html.erb"
        template "admin/sso_providers_form.html.erb", "app/views/admin/sso_providers/_form.html.erb"
        template "admin/dictionaries_index.html.erb", "app/views/admin/dictionaries/index.html.erb"
        template "admin/dictionaries_new.html.erb", "app/views/admin/dictionaries/new.html.erb"
        template "admin/dictionaries_edit.html.erb", "app/views/admin/dictionaries/edit.html.erb"
        template "admin/dictionaries_form.html.erb", "app/views/admin/dictionaries/_form.html.erb"
        template "admin/progress_jobs_index.html.erb", "app/views/admin/progress_jobs/index.html.erb"
        template "admin/scheduled_jobs_index.html.erb", "app/views/admin/scheduled_jobs/index.html.erb"
        template "admin/scheduled_jobs_new.html.erb", "app/views/admin/scheduled_jobs/new.html.erb"
        template "admin/scheduled_jobs_edit.html.erb", "app/views/admin/scheduled_jobs/edit.html.erb"
        template "admin/scheduled_jobs_form.html.erb", "app/views/admin/scheduled_jobs/_form.html.erb"
        template "admin/search_index.html.erb", "app/views/admin/search/index.html.erb"
      end

      def create_api
        template "api_base_controller.rb", "app/controllers/api/base_controller.rb"
      end

      def add_routes
        route <<~RUBY
          namespace :admin do
            root "dashboard#index"
            resource :session, only: %i[new create destroy] do
              get :mfa_challenge
              post :mfa_verify
              post :select_tenant
              post :sso_start     # home-realm discovery: email -> tenant IdP
              get  :sso_callback  # the IdP redirect target
            end
            resource :mfa, only: %i[show new create destroy], controller: "mfa"  # a user's own two-factor setup
            resource :sudo, only: %i[new create], controller: "sudo"             # step-up re-challenge
            resources :pending_actions, only: %i[index] do                       # the approval queue
              member do
                post :approve
                post :reject
              end
            end
            resources :perspectives, only: %i[index create update destroy] do    # saved table views
              post :set_default, on: :member
            end
            delete "record_lock", to: "record_locks#destroy"  # manager take-over of an edit lock
            get "events/stream", to: "events#stream", as: :events_stream  # SSE push (Loam::EventStream)
            resources :business_rules, only: %i[index new create edit update destroy]  # when/then rules
            resources :sso_providers, only: %i[index new create edit update destroy]  # per-tenant OIDC config
            resources :dictionaries, only: %i[index new create edit update destroy] do # managed lookup lists
              resources :entries, only: %i[create update destroy], controller: "dictionary_entries"
            end
            resources :progress_jobs, only: %i[index] do  # long-running task progress (live via SSE)
              post :cancel, on: :member
            end
            resources :scheduled_jobs, only: %i[index new create edit update destroy] do  # recurring jobs
              post :run_now, on: :member
            end
            resources :field_definitions, only: %i[index new create destroy]
            resources :notifications, only: %i[index] do
              post :mark_read, on: :member
            end
            resources :webhook_endpoints, only: %i[index new create destroy]
            resources :api_tokens, only: %i[index create destroy]
            resources :comments, only: %i[create]
            # Settings are keyed by a dotted string ("billing.currency"), which a
            # resourceful :id would truncate at the dot, so the key travels as a param.
            get    "configs",      to: "configs#index",  as: :configs
            get    "configs/edit", to: "configs#edit",   as: :edit_config
            patch  "configs",      to: "configs#update"
            delete "configs",      to: "configs#reset"
            # Feature flags are keyed by a dotted name too, so the name travels as a param.
            get    "features",         to: "features#index",   as: :features
            post   "features/enable",  to: "features#enable",  as: :enable_feature
            post   "features/disable", to: "features#disable", as: :disable_feature
            delete "features",         to: "features#reset"
            get "search", to: "search#index"
          end

          namespace :api do
            # `rails g loam:entity` injects `resources :<entities>` here.
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
