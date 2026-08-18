module Loam
  # Base policy. One policy class per entity, one instance per (actor, record)
  # pair. Action checks (read?/create?/update?/destroy?) default to "any member
  # of the current tenant"; field-level write access is declared, not coded:
  #
  #   class EquipmentPolicy < Loam::Policy
  #     field :daily_rate, writable: [:manager]
  #   end
  #
  # Roles come from Loam::Membership (actor + current tenant -> role).
  class Policy
    class << self
      def field_rules
        @field_rules ||= {}
      end

      def field(name, writable: nil)
        field_rules[name.to_sym] = { writable: writable }
      end

      def for(record)
        policy_class = "#{record.class.name}Policy".safe_constantize
        raise Error, "No policy defined for #{record.class.name} (expected #{record.class.name}Policy)" unless policy_class

        policy_class.new(Loam::Current.actor, record)
      end
    end

    attr_reader :actor, :record

    def initialize(actor, record)
      @actor = actor
      @record = record
    end

    def role
      return nil unless actor

      @role ||= Loam::Membership.find_by(user_id: actor.id)&.role&.to_sym
    end

    def member? = role.present?

    def read? = member?
    def create? = member?
    def update? = member?
    def destroy? = member?

    # Field-level check: fields without a declared rule are writable by any
    # member; fields with `writable:` only by the listed roles.
    def writable?(field_name)
      rule = self.class.field_rules[field_name.to_sym]
      return member? if rule.nil? || rule[:writable].nil?

      Array(rule[:writable]).map(&:to_sym).include?(role)
    end

    def permitted_fields(field_names)
      field_names.select { |f| writable?(f) }
    end
  end
end
