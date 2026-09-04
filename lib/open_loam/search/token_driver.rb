module OpenLoam
  module Search
    # A portable, word-level index (the flagship second driver). Each record's
    # searchable text is normalized into tokens stored in open_loam_search_tokens;
    # a query is tokenized the same way and matched with AND semantics — a record
    # must carry EVERY query token — so "excavator cat" finds "CAT 320 Excavator"
    # regardless of word order or position. Plain SQL: works on SQLite and
    # PostgreSQL, no external service, and genuinely better than LIKE (word-level,
    # order-independent). When an app outgrows even this, the same seam takes a
    # Meilisearch/Elasticsearch driver with no call-site change.
    #
    # Tenant isolation is free: OpenLoam::SearchToken is a TenantRecord, so both the
    # match subquery and every write are scoped to the current tenant.
    class TokenDriver < Driver
      class << self
        def search(model, query, scope:)
          tokens = tokenize(query)
          return scope if tokens.empty? || !model.open_loam_searchable?

          # AND semantics: keep only records carrying all N distinct query
          # tokens. Under AND every hit has the full match count, so ranking is
          # degenerate — ordering is left to the caller.
          matches = OpenLoam::SearchToken
            .where(searchable_type: type_for(model), token: tokens)
            .group(:searchable_id)
            .having("COUNT(DISTINCT token) = #{tokens.size}")
            .select(:searchable_id)

          scope.where(id: matches)
        end

        # Rebuild one record's tokens in place. Called from after_save; runs in
        # the record's tenant, so the token rows land in the right tenant.
        def index(record)
          model = record.class
          return unless model.open_loam_searchable?

          type = type_for(model)
          OpenLoam::SearchToken.where(searchable_type: type, searchable_id: record.id).delete_all

          tokens = tokenize(searchable_text(record))
          return if tokens.empty?

          rows = tokens.map do |token|
            { tenant_id: record.tenant_id, searchable_type: type, searchable_id: record.id, token: token }
          end
          OpenLoam::SearchToken.insert_all(rows)
        end

        def remove(record)
          OpenLoam::SearchToken.where(searchable_type: type_for(record.class), searchable_id: record.id).delete_all
        end

        # Rebuild every current-tenant record of a model — run inside
        # OpenLoam.as_tenant per tenant (the open_loam:search:reindex task does that).
        def reindex(model)
          OpenLoam::SearchToken.where(searchable_type: type_for(model)).delete_all
          model.find_each { |record| index(record) }
        end

        private

        def type_for(model) = model.name

        # THE SAFETY BOUNDARY: an encrypted column is skipped. Its stored value
        # is ciphertext (meaningless to tokenize), and tokenizing the PLAINTEXT
        # into a searchable table would recreate exactly the leak
        # OpenLoam::Encryptable closes — an encrypted field stays exact-match-only via
        # its blind index. `searchable_by` already refuses to declare an
        # encrypted column; this subtraction is the second line of that defense.
        def searchable_text(record)
          columns = record.class.open_loam_searchable_columns
          if record.class.respond_to?(:open_loam_encrypted_attributes)
            columns -= record.class.open_loam_encrypted_attributes
          end
          columns.map { |column| record.public_send(column) }.join(" ")
        end

        # Downcase, split on any run of non-alphanumeric (Unicode-aware, so
        # "Kraków" stays one token), drop blanks, de-dup. Deliberately NOT
        # linguistic — no stemming — for the prototype.
        def tokenize(text)
          text.to_s.downcase.split(/[^[:alnum:]]+/).reject(&:blank?).uniq
        end
      end
    end
  end
end
