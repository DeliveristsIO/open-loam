module Loam
  # Feature-string permissions with wildcards (L-705) — a fine-grained capability
  # layer that sits UNDER the coarse role. Roles answer "manager or clerk";
  # permissions answer "may this role do `equipment.edit`" without inventing a new
  # role for every distinction. Orthogonal to Loam::Policy (which gates field-level
  # writes on a record) and to Loam::Features (a per-tenant capability switch).
  #
  # Declared once, in the initializer (like broadcast_events / scheduler defaults):
  #
  #   Loam::Permissions.configure do
  #     role :admin,   allow: "*"                              # everything
  #     role :manager, allow: %w[equipment.* damage_report.* billing.read]
  #     role :clerk,   allow: %w[equipment.read damage_report.create]
  #   end
  #
  #   Loam::Permissions.allow?(:clerk, "equipment.read")  # => true
  #   Loam::Permissions.allow?(:clerk, "equipment.edit")  # => false
  #   Loam.can?("equipment.edit")                          # for the current actor's role
  #
  # DENY BY DEFAULT: a role with no matching grant (or no grants at all) is denied.
  #
  # Wildcards: `*` grants everything; a trailing `.*` is a prefix ("equipment.*"
  # matches "equipment.read" and "equipment.anything.deep", and "equipment"
  # itself); anything else is an exact match. (Deliberately not a full glob —
  # prefix + all covers the real cases; a mid-string `*` is not special.)
  module Permissions
    class << self
      def configure(&block)
        DSL.new.instance_eval(&block)
        registry
      end

      # Grant one role a pattern or list of patterns (additive).
      def role(name, allow:)
        registry[name.to_s] ||= []
        registry[name.to_s].concat(Array(allow).map(&:to_s)).uniq!
        registry[name.to_s]
      end

      def granted(role) = registry[role.to_s] || []

      def allow?(role, permission)
        return false if role.nil?

        granted(role).any? { |pattern| matches?(pattern, permission.to_s) }
      end

      # THE wildcard rule, in one place.
      def matches?(pattern, permission)
        pattern = pattern.to_s
        return true if pattern == "*"

        if pattern.end_with?(".*")
          prefix = pattern[0..-2]           # "equipment." (keep the dot)
          permission == pattern[0..-3] || permission.start_with?(prefix)
        else
          permission == pattern
        end
      end

      def reset!
        @registry = {}
      end

      private

      def registry
        @registry ||= {}
      end
    end

    # Tiny DSL so `configure { role ... }` reads well without a receiver.
    class DSL
      def role(name, allow:)
        Loam::Permissions.role(name, allow: allow)
      end
    end
  end
end
