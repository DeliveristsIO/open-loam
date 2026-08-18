module Admin
  # One box, every entity. Results are grouped by entity and limited per group,
  # so a broad query stays readable and cheap.
  #
  # Tenant isolation needs no work here: each model's `search` returns its own
  # tenant-scoped relation, so this can only ever find records the current
  # tenant owns.
  class SearchController < BaseController
    PER_ENTITY = 10

    helper_method :search_result_label

    def index
      @query = params[:q].to_s.strip
      @results = @query.blank? ? {} : search_all(@query)
    end

    # The first searchable column that has a value, plus the id — enough to
    # recognise a record without Loam having to know what a "title" is.
    def search_result_label(record)
      value = record.class.loam_searchable_columns.filter_map { |column| record.public_send(column).presence }.first

      [ value || record.model_name.human, "##{record.id}" ].join(" ")
    end

    private

    def search_all(query)
      searchable_models.filter_map do |model|
        records = model.search(query).order(id: :desc).limit(PER_ENTITY).to_a
        [ model, records ] if records.any?
      end.to_h
    end

    # Every Loam entity that opted into search, in name order.
    #
    # This eager loads, unlike Admin::CommentsController, and for the opposite
    # reason: there is no user-supplied class name to check here, we need the
    # COMPLETE list of models — and in development classes load lazily, so a
    # model nobody has touched yet would silently be missing from results.
    def searchable_models
      Rails.application.eager_load!

      Loam::TenantRecord.descendants.select do |model|
        model.respond_to?(:loam_searchable?) && model.loam_searchable?
      end.sort_by(&:name)
    end
  end
end
