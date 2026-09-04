module OpenLoam
  # Text search over an entity's own columns:
  #
  #   class Equipment < OpenLoam::TenantRecord
  #     include OpenLoam::Searchable
  #     searchable_by :name, :status
  #   end
  #
  #   Equipment.search("cat")   # => a relation, still tenant-scoped
  #
  # `search` returns a relation, so tenant isolation is not something this has
  # to remember: the default scope is already on it, and the result composes
  # with ordering, pagination and anything else.
  #
  # HOW a query matches is a swappable driver (OpenLoam::Search.driver): the default
  # LikeDriver is a substring LIKE; the TokenDriver is a portable word-level
  # index; an external engine is a third. This concern is only the DECLARATION
  # (`searchable_by`) and the untouched call site (`Model.search(q)`) — swapping
  # the driver changes neither. See OpenLoam::Search.
  module Searchable
    extend ActiveSupport::Concern

    included do
      class_attribute :open_loam_searchable_columns, default: [].freeze, instance_writer: false

      # Keep the active driver's index current. A no-op under the default
      # LikeDriver; the TokenDriver maintains open_loam_search_tokens here. Guarded so
      # non-searchable models pay nothing, and skipped when no searchable column
      # actually changed — so a soft-delete (which touches only deleted_at)
      # leaves the tokens in place, and the base scope hides the row anyway.
      #
      # `respond_to?` guard: Searchable is includable in a plain class purely to
      # exercise the `searchable_by` DSL (its encrypted-field check), with no
      # ActiveRecord underneath — only a real model gets the callbacks.
      if respond_to?(:after_save)
        after_save    :open_loam_update_search_index,     if: :open_loam_search_index_stale?
        after_destroy :open_loam_remove_from_search_index, if: -> { self.class.open_loam_searchable? }
      end
    end

    class_methods do
      # Declared columns are code, not input — no runtime validation here,
      # because reading the schema at class-definition time would need a
      # database connection just to boot.
      def searchable_by(*columns)
        columns = columns.map(&:to_s)

        # The mirror of OpenLoam::Encryptable's check: an encrypted column is
        # ciphertext at rest, which LIKE cannot match. Caught here when
        # `searchable_by` is the later declaration (encrypts catches the reverse).
        if respond_to?(:open_loam_encrypted_attributes)
          conflict = columns & open_loam_encrypted_attributes
          if conflict.any?
            raise OpenLoam::Error,
                  "#{name}: cannot `searchable_by` encrypted field(s) #{conflict.join(', ')} — " \
                  "ciphertext cannot be LIKE-searched. Use `encrypts :field, searchable: true` " \
                  "for exact-match lookup instead."
          end
        end

        self.open_loam_searchable_columns = columns.freeze
      end

      def open_loam_searchable?
        open_loam_searchable_columns.any?
      end

      # Delegates to the active driver, handing it the current relation as the
      # base scope — so `Model.search(q)` and `some_scope.search(q)` both work
      # (a class method called on a relation runs with `all` == that relation).
      # A blank query returns everything: an empty search box means "no filter".
      def search(query)
        OpenLoam::Search.search(self, query, scope: all)
      end
    end

    private

    def open_loam_update_search_index     = OpenLoam::Search.index(self)
    def open_loam_remove_from_search_index = OpenLoam::Search.remove(self)

    # On create every column counts as changed, so a new record is always
    # indexed; on update, reindex only when a searchable column actually moved.
    def open_loam_search_index_stale?
      return false unless self.class.open_loam_searchable?

      saved_changes.keys.intersect?(self.class.open_loam_searchable_columns)
    end
  end
end
