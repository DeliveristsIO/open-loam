module Loam
  module Search
    # The driver contract. Subclass and override the class methods.
    #
    #   search(model, query, scope:) -> a relation
    #     Return a subset of `scope` (already tenant-scoped, and any saved-view
    #     filter already applied) matching `query`. MUST return a relation so it
    #     composes with the caller's own `.where`/`.order`/`.limit`. A blank
    #     query returns `scope` unchanged (an empty search box is "no filter").
    #
    #   index(record) / remove(record)
    #     Maintain the driver's index as records are saved and destroyed. Called
    #     from Loam::Searchable's after_save / after_destroy.
    #
    #   reindex(model)
    #     Rebuild the index for a model (used by `loam:search:reindex` and seeds).
    #
    # A driver that needs no index (LIKE) leaves index/remove/reindex as no-ops.
    class Driver
      class << self
        def search(model, query, scope:)
          raise NotImplementedError, "#{name} must implement .search(model, query, scope:)"
        end

        def index(record) = nil
        def remove(record) = nil
        def reindex(model) = nil
      end
    end
  end
end
