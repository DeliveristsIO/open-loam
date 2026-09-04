module Loam
  # The word-level search index maintained by Loam::Search::TokenDriver: one row
  # per (record, token), tenant-scoped like every Loam entity. Plumbing — not
  # audited, not soft-deletable. Only the TokenDriver reads or writes it; under
  # the default LikeDriver this table simply stays empty.
  class SearchToken < Loam::TenantRecord
    self.table_name = "loam_search_tokens"
  end
end
