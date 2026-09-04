module Loam
  # Runtime, migration-free fields — stored in the `custom_fields` json
  # column every generated entity table carries. Included automatically by
  # `rails g loam:entity`. Shape is declared at runtime via a
  # Loam::FieldDefinition (typically through the admin "Field definitions"
  # screen), not in code — that's what makes it migration-free.
  #
  #   equipment.custom_field(:serial_number)                # => "SN-123" (cast)
  #   equipment.set_custom_field(:serial_number, "SN-123")
  #
  # Reading/writing a name with no matching Loam::FieldDefinition for this
  # tenant + entity raises Loam::UnknownCustomFieldError immediately — the
  # same "fail loudly at the access site" philosophy as Loam.tenant!.
  module CustomFields
    extend ActiveSupport::Concern

    included do
      # Keep the read-model index (Loam::CustomFieldIndex) current so custom-field
      # filter/sort is index-backed. Re-project only when the custom_fields column
      # actually changed (a soft-delete touches only deleted_at, so the rows stay
      # and the base scope hides the record — the L-912 posture). A no-op for a
      # model with no custom_fields column. Guarded by respond_to? so Loam::
      # CustomFields stays includable in a plain class for a DSL-only test.
      if respond_to?(:after_save)
        after_save    :loam_reindex_custom_fields, if: :loam_custom_fields_dirty?
        after_destroy :loam_deindex_custom_fields
      end
    end

    class_methods do
      def custom_field_definitions
        Loam::FieldDefinition.where(entity_type: name)
      end
    end

    def custom_field(name)
      definition = custom_field_definition!(name)
      cast_custom_field(definition.field_type, custom_fields[definition.name])
    end

    def set_custom_field(name, value)
      definition = custom_field_definition!(name)
      custom_fields[definition.name] = serialize_custom_field(definition.field_type, value)
      value
    end

    # The display label for a custom field. For a dictionary-typed field this is
    # the matching entry's label; for every other type it is just the value. A
    # dictionary value is stored as its plain code, so read/write is unchanged —
    # only the human-facing rendering differs.
    def custom_field_label(name)
      definition = custom_field_definition!(name)
      value = custom_field(name)
      return value unless definition.field_type == "dictionary"

      Loam::Dictionaries.label_for(definition.dictionary_key, value)
    end

    private

    def loam_reindex_custom_fields = Loam::CustomFieldIndex.project(self)
    def loam_deindex_custom_fields = Loam::CustomFieldIndex.remove(self)

    def loam_custom_fields_dirty?
      return false unless self.class.respond_to?(:custom_field_definitions)

      # On create every column counts as changed; on update, only re-project when
      # the custom_fields json actually moved.
      respond_to?(:saved_change_to_custom_fields?) ? saved_change_to_custom_fields? : true
    end

    def custom_field_definition!(name)
      custom_field_definitions_by_name.fetch(name.to_s) do
        raise UnknownCustomFieldError, "No Loam::FieldDefinition named #{name.inspect} for #{self.class.name} " \
                                       "(tenant #{Loam.tenant&.id.inspect})"
      end
    end

    # Memoized per-instance: several fields are typically read/written per
    # request, and definitions vary per tenant so they can't be cached on the
    # class itself.
    def custom_field_definitions_by_name
      @custom_field_definitions_by_name ||= self.class.custom_field_definitions.index_by(&:name)
    end

    def cast_custom_field(type, raw)
      return nil if raw.nil?

      case type.to_s
      when "integer" then raw.to_i
      when "decimal" then BigDecimal(raw.to_s)
      when "boolean" then ActiveModel::Type::Boolean.new.cast(raw)
      when "date" then Date.parse(raw.to_s)
      when "datetime" then Time.zone.parse(raw.to_s)
      else raw.to_s
      end
    end

    def serialize_custom_field(type, value)
      return nil if value.nil? || value == ""

      case type.to_s
      when "integer" then value.to_i
      when "decimal" then value.to_s
      when "boolean" then ActiveModel::Type::Boolean.new.cast(value)
      when "date" then value.is_a?(Date) ? value.iso8601 : Date.parse(value.to_s).iso8601
      when "datetime"
        value.is_a?(Time) || value.is_a?(DateTime) ? value.utc.iso8601 : Time.zone.parse(value.to_s).utc.iso8601
      else
        value.to_s
      end
    end
  end
end
