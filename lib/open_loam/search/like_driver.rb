module OpenLoam
  module Search
    # The default driver: a substring LIKE across the declared columns — exactly
    # the original OpenLoam::Searchable behavior, now behind the seam. Portable
    # (Arel's `matches` emits ILIKE on PostgreSQL, case-insensitive LIKE on
    # SQLite for ASCII) and needs no index, so index/remove/reindex are no-ops.
    #
    # What it does NOT do — ignore accents, split on words, rank — is the reason
    # the seam exists: swap in OpenLoam::Search::TokenDriver (or an external engine)
    # and every `Model.search(q)` call site keeps working unchanged.
    class LikeDriver < Driver
      class << self
        def search(model, query, scope:)
          query = query.to_s.strip
          return scope if query.blank? || !model.open_loam_searchable?

          # sanitize_sql_like escapes the LIKE wildcards so a literal % or _ in
          # the query stays literal; the second arg to `matches` declares that
          # escape character to the database (SQLite has none by default).
          pattern = "%#{model.sanitize_sql_like(query)}%"
          conditions = model.open_loam_searchable_columns.map do |column|
            model.arel_table[column].matches(pattern, "\\")
          end
          scope.where(conditions.inject(:or))
        end
      end
    end
  end
end
