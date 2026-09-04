module OpenLoam
  # A saved view of an entity's admin index — which columns show, active filters,
  # sort, and page size — that a user can name, make their default, or share.
  #
  # Three visibility tiers, widening in audience:
  #   * "private" — only its owner sees it (owner_id).
  #   * "role"    — everyone with the named membership role in the tenant.
  #   * "tenant"  — everyone in the tenant.
  # A private view is invisible to others by construction (see
  # OpenLoam::Perspectives.visible_to), not merely by a permission check.
  #
  # Tenant-scoped like everything else, and audited. Optimistic-locked
  # (lock_version) so two people editing a shared view don't silently clobber
  # each other — the admin controller rescues ActiveRecord::StaleObjectError.
  class Perspective < OpenLoam::TenantRecord
    self.table_name = "open_loam_perspectives"

    include OpenLoam::Auditable

    VISIBILITIES = %w[private role tenant].freeze

    # Columns a saved filter/sort may NEVER touch: tenant_id is enforced by the
    # default scope (a filter on it is a footgun, not a leak), and the rest are
    # plumbing, not data. Everything else on the entity is fair game.
    NON_FILTERABLE = %w[id tenant_id lock_version deleted_at created_at updated_at].freeze

    belongs_to :owner, class_name: "User", optional: true

    validates :entity_type, :name, presence: true
    validates :visibility, inclusion: { in: VISIBILITIES }
    validates :role, presence: true, if: -> { visibility == "role" }

    # Apply this view's stored filters and sort to a base scope, returning a
    # relation (columns and page_size are read by the controller/view). SAFE BY
    # CONSTRUCTION: a filter or sort key is honored only if it names a real,
    # non-plumbing column of the entity — a crafted key (arbitrary SQL, or
    # tenant_id) is skipped, never executed. Values ride as hash conditions, so
    # Active Record quotes them.
    def apply(scope)
      allowed = filterable_columns(scope.klass)
      filters = config_hash("filters")

      # A free-text "q" runs the entity's own Searchable search when it has one;
      # on a non-searchable entity `search` returns `all`, so this safely no-ops.
      if filters["q"].present? && scope.klass.respond_to?(:search)
        scope = scope.search(filters["q"])
      end

      filters.each do |column, value|
        next if column == "q"
        next unless allowed.include?(column.to_s)

        scope = scope.where(column => value)
      end

      sort = config_hash("sort")
      if allowed.include?(sort["field"].to_s)
        # reorder (not order) so the saved sort REPLACES the base order; id keeps
        # pagination stable when the sort column has ties.
        direction = sort["dir"].to_s == "desc" ? :desc : :asc
        scope = scope.reorder(sort["field"] => direction, id: :desc)
      end

      scope
    end

    def columns
      Array(config_hash_root["columns"])
    end

    def page_size
      config_hash_root["page_size"]
    end

    # Make this the default for its audience, unsetting the sibling default it
    # would otherwise compete with (same entity + visibility, and same owner/role
    # where those narrow the audience).
    def make_default!
      siblings = self.class.where(entity_type: entity_type, visibility: visibility).where.not(id: id)
      siblings = siblings.where(owner_id: owner_id) if visibility == "private"
      siblings = siblings.where(role: role) if visibility == "role"

      transaction do
        siblings.update_all(is_default: false)
        update!(is_default: true)
      end
    end

    private

    def filterable_columns(klass)
      klass.column_names - NON_FILTERABLE
    end

    def config_hash_root
      config.is_a?(Hash) ? config : {}
    end

    def config_hash(key)
      value = config_hash_root[key]
      value.is_a?(Hash) ? value : {}
    end
  end
end
