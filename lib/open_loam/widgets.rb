module OpenLoam
  # A registry of dashboard widgets — small, module-provided tiles (a metric, a
  # short list) shown on the admin home. A widget is a DATA PROVIDER plus a
  # title and an optional role filter; it never renders arbitrary code:
  #
  #   OpenLoam::Widgets.register(key: "open_rentals", title: "Open rentals", roles: %w[manager]) do |actor|
  #     { kind: "count", value: Rental.where(status: "open").count }   # tenant-scoped query
  #   end
  #
  # The provider returns a small data hash (`{ kind: "count", value: }` or
  # `{ kind: "list", items: [...] }`); the dashboard renders it generically.
  # Widgets run tenant-scoped (query through tenant-scoped models), the `roles:`
  # filter is enforced server-side (a hidden widget's data is NOT computed), and
  # a raising provider is isolated into an error tile — the dashboard never breaks.
  module Widgets
    Widget = Struct.new(:key, :title, :roles, :provider, keyword_init: true) do
      def visible_to?(role)
        roles.nil? || Array(roles).map(&:to_s).include?(role.to_s)
      end
    end

    class << self
      def register(key:, title:, roles: nil, &block)
        registry[key.to_s] = Widget.new(key: key.to_s, title: title, roles: roles, provider: block)
        key.to_s
      end

      def registered = registry.values
      def keys = registry.keys
      def find(key) = registry[key.to_s]

      def reset!
        @registry = {}
      end

      # Resolve a widget for (actor, role): nil when it doesn't exist or the role
      # can't see it (so its data is never computed), otherwise
      # { key, title, data } — or { key, title, error: } when the provider raises.
      def resolve(key, actor:, role:)
        return nil if OpenLoam::Overrides.disabled?(:widgets, key) # customization without forking

        widget = find(key)
        return nil unless widget&.visible_to?(role)

        provider = OpenLoam::Overrides.replacement(:widgets, key) || widget.provider
        { key: widget.key, title: widget.title, data: provider.call(actor) }
      rescue StandardError => error
        { key: widget&.key, title: widget&.title, error: error.message }
      end

      # The widgets every OpenLoam app starts with — registered at boot from the
      # engine, so a fresh install has a useful default dashboard.
      def register_builtins!
        register(key: "audit_recent", title: "Recent activity") do |_actor|
          items = OpenLoam::AuditRecord.order(created_at: :desc).limit(8)
                                   .map { |a| "#{a.action} #{a.auditable_type} ##{a.auditable_id}" }
          { kind: "list", items: items }
        end
        register(key: "notifications_unread", title: "Unread notifications") do |actor|
          { kind: "count", value: OpenLoam::Notification.unread.where(user_id: actor&.id).count }
        end
        register(key: "pending_approvals", title: "Pending approvals", roles: %w[manager]) do |_actor|
          { kind: "count", value: OpenLoam::PendingAction.pending.count }
        end
        register(key: "open_progress", title: "Running tasks") do |_actor|
          { kind: "count", value: OpenLoam::ProgressJob.where(status: "running").count }
        end
      end

      private

      def registry
        @registry ||= {}
      end
    end
  end
end
