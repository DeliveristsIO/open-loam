module Loam
  # The search seam. `Model.search(q)` and the `searchable_by` declaration never
  # change; the STRATEGY behind them is a swappable driver:
  #
  #   Loam::Search.driver = Loam::Search::TokenDriver   # in an initializer
  #
  # The default is the LIKE driver — portable and zero-setup — so nothing
  # changes out of the box. A driver turns a text query into a subset of an
  # already-tenant-scoped relation and maintains whatever index it needs; see
  # Loam::Search::Driver for the contract. This is the same shape as
  # Loam::EventStream.broadcaster and Loam::Enrichers: one seam, drivers behind
  # it, callers untouched.
  module Search
    class << self
      attr_writer :driver

      def driver
        @driver ||= Loam::Search::LikeDriver
      end

      def search(model, query, scope:) = driver.search(model, query, scope: scope)
      def index(record)  = driver.index(record)
      def remove(record) = driver.remove(record)
      def reindex(model) = driver.reindex(model)
    end
  end
end
