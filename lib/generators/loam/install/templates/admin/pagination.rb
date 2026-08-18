module Admin
  # Pagination with no gem attached — the smallest thing that works:
  #
  #   @records, @page, @has_next = paginate(Equipment.order(created_at: :desc))
  #
  # Swap in pagy or kaminari when you need total counts, numbered pages or a
  # window of links; callers only ever use these three values, so the change
  # stays inside this module and the index views.
  module Pagination
    PER_PAGE = 25

    def paginate(scope, per_page: PER_PAGE)
      page = params[:page].to_i
      page = 1 if page < 1

      # One row more than a page is fetched and never rendered: it answers
      # "is there a next page?" without a second COUNT over the whole table.
      records = scope.limit(per_page + 1).offset((page - 1) * per_page).to_a

      [ records.first(per_page), page, records.size > per_page ]
    end
  end
end
