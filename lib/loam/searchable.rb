module Loam
  # Text search over an entity's own columns:
  #
  #   class Equipment < Loam::TenantRecord
  #     include Loam::Searchable
  #     searchable_by :name, :status
  #   end
  #
  #   Equipment.search("cat")   # => a relation, still tenant-scoped
  #
  # `search` returns a relation, so tenant isolation is not something this has
  # to remember: the default scope is already on it, and the result composes
  # with ordering, pagination and anything else.
  #
  # Matching is a plain substring LIKE. What that means per adapter, because it
  # is not the same everywhere: on SQLite, LIKE ignores case for ASCII; on
  # PostgreSQL, Arel's `matches` emits ILIKE, which ignores case properly. What
  # neither does is ignore accents, stem words or rank results — when the app
  # needs that, this is the seam to replace (pg_trgm, tsvector, Elasticsearch)
  # and every caller keeps working.
  module Searchable
    extend ActiveSupport::Concern

    included do
      class_attribute :loam_searchable_columns, default: [].freeze, instance_writer: false
    end

    class_methods do
      # Declared columns are code, not input — no runtime validation here,
      # because reading the schema at class-definition time would need a
      # database connection just to boot.
      def searchable_by(*columns)
        columns = columns.map(&:to_s)

        # The mirror of Loam::Encryptable's check: an encrypted column is
        # ciphertext at rest, which LIKE cannot match. Caught here when
        # `searchable_by` is the later declaration (encrypts catches the reverse).
        if respond_to?(:loam_encrypted_attributes)
          conflict = columns & loam_encrypted_attributes
          if conflict.any?
            raise Loam::Error,
                  "#{name}: cannot `searchable_by` encrypted field(s) #{conflict.join(', ')} — " \
                  "ciphertext cannot be LIKE-searched. Use `encrypts :field, searchable: true` " \
                  "for exact-match lookup instead."
          end
        end

        self.loam_searchable_columns = columns.freeze
      end

      def loam_searchable?
        loam_searchable_columns.any?
      end

      # A blank query matches everything rather than nothing: an empty search
      # box means "no filter", which is what a user expects from one.
      def search(query)
        query = query.to_s.strip
        return all if query.blank? || !loam_searchable?

        # sanitize_sql_like escapes the LIKE wildcards so a literal % or _ in
        # the query stays literal; the second argument to `matches` is what
        # declares that escape character to the database (SQLite has none by
        # default, so without it the escaping would be worse than useless).
        pattern = "%#{sanitize_sql_like(query)}%"
        conditions = loam_searchable_columns.map { |column| arel_table[column].matches(pattern, "\\") }

        where(conditions.inject(:or))
      end
    end
  end
end
