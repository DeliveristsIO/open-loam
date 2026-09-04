module Loam
  # Per-record, per-locale translations of DATA fields — a product name, a
  # category label — distinct from Rails i18n (developer UI strings, still
  # Rails-native and out of scope here).
  #
  #   class Equipment < Loam::TenantRecord
  #     include Loam::Translatable
  #     translates :name, :description
  #   end
  #
  # READ OVERLAY: the field reader returns the translation for the CURRENT locale
  # (Loam.locale) when one exists, else the record's own COLUMN value — the base
  # is the fallback and stays authoritative for the default locale:
  #
  #   equipment.name                  # => overlay for Loam.locale, else base
  #   equipment.name(locale: "de")    # => explicit locale, else base
  #   equipment.set_translation(:name, "de", "Bagger")
  #   equipment.translations_for(:name)  # => { "de" => "Bagger", ... }
  #
  # Writes still go through the ordinary `name=` writer to the base column, so
  # translations are purely additive rows in loam_translations — the base value
  # is never overwritten or lost.
  module Translatable
    extend ActiveSupport::Concern

    included do
      class_attribute :loam_translatable_attributes, default: [].freeze, instance_writer: false

      has_many :loam_translations, class_name: "Loam::Translation",
               as: :translatable, dependent: :delete_all
    end

    class_methods do
      def translates(*names)
        names = names.map(&:to_s)

        # An encrypted field must NOT be translatable: a translation row would
        # store its PLAINTEXT in loam_translations, recreating exactly the leak
        # Loam::Encryptable closes (same posture as searchable_by's refusal).
        if respond_to?(:loam_encrypted_attributes)
          conflict = names & loam_encrypted_attributes
          if conflict.any?
            raise Loam::Error,
                  "#{name}: cannot `translates` encrypted field(s) #{conflict.join(', ')} — " \
                  "a translation would store plaintext. Encrypted data is not translatable."
          end
        end

        self.loam_translatable_attributes = (loam_translatable_attributes + names).freeze

        names.each do |field|
          # The overlay reader. `read_attribute` (not super) is the base value,
          # so it works regardless of AR's lazy attribute-method definition.
          define_method(field) do |locale: nil|
            loam_translation_value(field, locale) || read_attribute(field)
          end
        end
      end

      def loam_translatable?(field)
        loam_translatable_attributes.include?(field.to_s)
      end
    end

    # The stored translation for a field in a locale (default: the current one),
    # or nil when there is none.
    def loam_translation_value(field, locale = nil)
      locale = (locale || Loam.locale).to_s
      return nil if locale.blank?

      loam_translations.detect { |t| t.field == field.to_s && t.locale == locale }&.value
    end

    def set_translation(field, locale, value)
      raise Loam::Error, "#{field} is not translatable on #{self.class.name}" unless self.class.loam_translatable?(field)

      row = loam_translations.find_or_initialize_by(field: field.to_s, locale: locale.to_s)
      row.value = value
      row.save!
      loam_translations.reset
      value
    end

    def translations_for(field)
      loam_translations.select { |t| t.field == field.to_s }.to_h { |t| [ t.locale, t.value ] }
    end
  end
end
