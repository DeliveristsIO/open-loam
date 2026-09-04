module OpenLoam
  module BusinessRules
    # The SAFE condition evaluator — the critical security boundary of the rules
    # engine. A rule is DATA an admin edits, so this must NEVER run arbitrary
    # code: it supports only `and`/`or`/`not` and leaf comparisons
    # `{ field, op, value }`, and a `field` may name ONLY a real, non-plumbing,
    # non-encrypted column of the record OR a declared custom field. Anything
    # else is refused — no `send` of arbitrary methods, no SQL, no eval.
    module Condition
      OPS = %w[eq neq gt gte lt lte in contains present blank].freeze
      REFUSED = :__loam_field_refused__

      def self.matches?(node, record)
        node = node.is_a?(Hash) ? node : {}
        return true if node.empty? # no condition = always fires

        if node.key?("and")
          Array(node["and"]).all? { |child| matches?(child, record) }
        elsif node.key?("or")
          Array(node["or"]).any? { |child| matches?(child, record) }
        elsif node.key?("not")
          !matches?(node["not"], record)
        else
          leaf(node, record)
        end
      end

      def self.leaf(node, record)
        op = node["op"].to_s
        return false unless OPS.include?(op)

        actual = read_field(node["field"].to_s, record)
        return false if actual == REFUSED # an un-whitelisted field never matches

        compare(op, actual, node["value"])
      end

      # A whitelisted read, or REFUSED. `tenant_id` is refused as an isolation
      # footgun; ENCRYPTED columns are refused because a contains/eq rule over
      # their decrypted value would be an oracle leaking the secret through the
      # rule's behaviour. Everything unknown is refused, never sent.
      def self.read_field(field, record)
        klass = record.class
        return REFUSED if refused_column?(klass, field)

        if klass.column_names.include?(field)
          record.public_send(field)
        elsif custom_field?(record, field)
          begin
            record.custom_field(field)
          rescue OpenLoam::UnknownCustomFieldError
            REFUSED
          end
        else
          REFUSED
        end
      end

      def self.refused_column?(klass, field)
        return true if field == "tenant_id"

        klass.respond_to?(:open_loam_encrypted_attributes) &&
          klass.open_loam_encrypted_attributes.map(&:to_s).include?(field)
      end

      def self.custom_field?(record, field)
        record.class.respond_to?(:custom_field_definitions) &&
          record.class.custom_field_definitions.exists?(name: field)
      end

      def self.compare(op, actual, expected)
        case op
        when "eq"       then values_equal?(actual, expected)
        when "neq"      then !values_equal?(actual, expected)
        when "in"       then Array(expected).map(&:to_s).include?(actual.to_s)
        when "contains" then actual.to_s.include?(expected.to_s)
        when "present"  then actual.present?
        when "blank"    then actual.blank?
        else
          cmp = numeric_compare(actual, expected)
          return false if cmp.nil?

          { "gt" => cmp.positive?, "gte" => cmp >= 0, "lt" => cmp.negative?, "lte" => cmp <= 0 }[op]
        end
      end

      def self.values_equal?(actual, expected)
        actual == expected || actual.to_s == expected.to_s || numeric_compare(actual, expected)&.zero? || false
      end

      # Compare as numbers when both coerce; else fall back to the natural
      # comparison; incomparable types yield nil (so the op is simply false).
      def self.numeric_compare(actual, expected)
        Float(actual) <=> Float(expected)
      rescue ArgumentError, TypeError
        actual <=> expected
      rescue StandardError
        nil
      end
    end
  end
end
