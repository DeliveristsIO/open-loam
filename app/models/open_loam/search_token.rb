module OpenLoam
  # The word-level search index maintained by OpenLoam::Search::TokenDriver: one row
  # per (record, token), tenant-scoped like every OpenLoam entity. Plumbing — not
  # audited, not soft-deletable. Only the TokenDriver reads or writes it; under
  # the default LikeDriver this table simply stays empty.
  class SearchToken < OpenLoam::TenantRecord
    self.table_name = "open_loam_search_tokens"
  end
end
