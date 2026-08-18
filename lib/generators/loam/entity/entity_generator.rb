require "rails/generators"
require "rails/generators/active_record"

module Loam
  module Generators
    # `rails g loam:entity Equipment name:string daily_rate:decimal --domain rental`
    #
    # THE interface for adding a business entity — for humans and AI agents
    # alike. One command produces a tenant-scoped, audited, evented model, its
    # policy, an admin screen, and the isolation tests that prove the
    # guardrails hold. No decisions about how tenancy/permissions work: Loam
    # already decided.
    class EntityGenerator < Rails::Generators::NamedBase
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      argument :attributes, type: :array, default: [], banner: "field:type field:type"
      class_option :domain, type: :string, default: "app",
                            desc: "Event domain prefix (-> domain.entity.created)"

      def create_migration_file
        migration_template "migration.rb", "db/migrate/create_#{table_name}.rb"
      end

      def create_model
        template "model.rb", "app/models/#{file_name}.rb"
      end

      def create_policy
        template "policy.rb", "app/policies/#{file_name}_policy.rb"
      end

      def create_admin_controller
        template "controller.rb", "app/controllers/admin/#{plural_file_name}_controller.rb"
      end

      def create_api_controller
        template "api_controller.rb", "app/controllers/api/#{plural_file_name}_controller.rb"
      end

      def create_admin_views
        template "views/index.html.erb", "app/views/admin/#{plural_file_name}/index.html.erb"
        template "views/show.html.erb", "app/views/admin/#{plural_file_name}/show.html.erb"
        template "views/new.html.erb", "app/views/admin/#{plural_file_name}/new.html.erb"
        template "views/edit.html.erb", "app/views/admin/#{plural_file_name}/edit.html.erb"
        template "views/_form.html.erb", "app/views/admin/#{plural_file_name}/_form.html.erb"
      end

      def create_entity_test
        template "entity_test.rb", "test/entities/#{file_name}_test.rb"
      end

      # `namespace:` makes Rails inject the route INTO the existing
      # `namespace :admin do` block (the one loam:install wrote) instead of
      # stacking one admin block per entity, and falls back to creating the
      # block when there is none. Re-running the generator is a no-op: the
      # injection is `force: false`, so identical routing code is skipped.
      # The API line carries `defaults: { format: :json }` — it is what an API
      # namespace wants anyway, and it also has to differ textually from the
      # admin line above: Rails' route injection skips code the file already
      # contains (that is what makes re-running this generator a no-op), so two
      # identical `resources :gadgets` lines would leave the second one out.
      def add_route
        route "resources :#{plural_file_name}", namespace: :admin
        route "resources :#{plural_file_name}, defaults: { format: :json }", namespace: :api
      end

      def print_next_steps
        say ""
        say "Entity #{class_name} created. Next:", :green
        say "  1. bin/rails db:migrate"
        say "  2. Declare field-level permissions in app/policies/#{file_name}_policy.rb"
        say "  3. bin/rails test"
      end

      private

      def domain
        options[:domain]
      end

      def field_names
        attributes.map(&:name)
      end

      # Only text-ish columns are worth a LIKE (see Loam::Searchable), so an
      # entity with none gets no `searchable_by` declaration and stays out of
      # the global search.
      def searchable_attributes
        attributes.select { |attribute| %i[string text].include?(attribute.type) }
      end

      # A plausible literal per attribute type, used by the generated test.
      def sample_value(attribute, variant = 0)
        case attribute.type
        when :integer, :bigint, :references then 1 + variant
        when :decimal, :float then "%.2f" % (9.99 + variant)
        when :boolean then (variant.zero? ? "true" : "false")
        when :date then "Date.new(2026, 1, #{1 + variant})"
        when :datetime, :time, :timestamp then "Time.utc(2026, 1, #{1 + variant})"
        else "\"Sample #{attribute.name} #{variant}\""
        end
      end

      def sample_attributes(variant = 0)
        attributes.map { |a| "#{a.name}: #{sample_value(a, variant)}" }.join(", ")
      end

      def first_field
        field_names.first || "tenant_id"
      end

      def form_field_helper(attribute)
        case attribute.type
        when :boolean then "check_box"
        when :text then "text_area"
        when :date then "date_field"
        when :datetime, :time, :timestamp then "datetime_field"
        when :integer, :bigint, :decimal, :float, :references then "number_field"
        else "text_field"
        end
      end
    end
  end
end
