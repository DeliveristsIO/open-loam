module Loam
  module Generators
    # Shared primary-key shaping for `loam:install` and `loam:entity`.
    #
    # Loam's migrations used to spell every key `bigint` — implicitly in
    # `create_table`, and explicitly in `t.references` and the polymorphic
    # `*_id` columns. In an app whose own tables use string or uuid keys the
    # foreign keys then do not line up with the tables they point at, and every
    # generated migration has to be hand-edited after the generator runs.
    #
    # The key type is taken from, in order: an explicit --primary-key-type, the
    # host app's own `config.generators` setting (so an app that already told
    # Rails what its keys look like does not have to tell Loam separately), and
    # bigint as the Rails default.
    #
    # The templates ask for the *rendered fragment* rather than the type, so
    # bigint keeps emitting exactly the migrations it emitted before — no `id:`
    # and no `type:` — and only a non-default key type adds anything.
    module PrimaryKeyOptions
      SUPPORTED = %w[bigint uuid string].freeze

      # varchar(36) is the usual shape for a UUID stored as a string, and it is
      # the case in the report that prompted this. An app that stores them some
      # other width passes --key-limit.
      DEFAULT_STRING_LIMIT = 36

      def self.included(base)
        base.class_option :primary_key_type, type: :string, default: nil,
                                             desc: "Key type for the generated tables: #{SUPPORTED.join(', ')}. " \
                                                   "Defaults to the app's config.generators primary_key_type, then bigint."
        base.class_option :key_limit, type: :numeric, default: nil,
                                      desc: "Column limit for a string key (default #{DEFAULT_STRING_LIMIT}). Ignored for bigint and uuid."
      end

      private

      def loam_key_type
        @loam_key_type ||= begin
          requested = (options[:primary_key_type] || host_app_primary_key_type).to_s
          requested = "bigint" if requested.empty?

          unless SUPPORTED.include?(requested)
            raise Thor::Error,
                  "Unsupported --primary-key-type #{requested.inspect}. Loam generates #{SUPPORTED.join(', ')}. " \
                  "A key type Loam does not know how to size would produce migrations that look right and " \
                  "do not line up with your tables."
          end

          requested.to_sym
        end
      end

      # What the host app already told Rails its keys look like. Absent outside
      # a booted application (the generator specs), which is the bigint case.
      def host_app_primary_key_type
        return nil unless defined?(Rails) && Rails.application

        Rails.application.config.generators.options.dig(:active_record, :primary_key_type)
      rescue StandardError
        nil
      end

      def loam_key_limit
        return options[:key_limit].to_i if options[:key_limit]

        loam_key_type == :string ? DEFAULT_STRING_LIMIT : nil
      end

      # Appended to `create_table :x` — "" for bigint, so the default path is
      # byte-for-byte what it was.
      def loam_id_option
        return "" if loam_key_type == :bigint

        "#{loam_key_fragment.sub('type:', 'id:')}"
      end

      # Appended inside `t.references :x, ...`.
      def loam_type_option
        return "" if loam_key_type == :bigint

        loam_key_fragment
      end

      # The bare column type for a polymorphic or un-constrained `*_id`, which
      # cannot use t.references.
      def loam_key_column_type
        loam_key_type
      end

      def loam_key_limit_option
        loam_key_limit ? ", limit: #{loam_key_limit}" : ""
      end

      def loam_key_fragment
        fragment = ", type: :#{loam_key_type}"
        fragment += ", limit: #{loam_key_limit}" if loam_key_limit
        fragment
      end
    end
  end
end
