module Admin
  # Per-record content translations (OpenLoam::Translatable) — manager-only, since
  # translating content is a privileged edit. Scoped by translatable_type +
  # translatable_id; edits each translatable field across OpenLoam.locales. The base
  # (default-locale) value stays on the record itself and is shown read-only for
  # reference — translations are additive.
  class TranslationsController < BaseController
    before_action { require_role!(:manager) }
    before_action :set_record

    def index; end

    def update
      params.require(:translations).to_unsafe_h.each do |field, by_locale|
        next unless @record.class.open_loam_translatable?(field)

        by_locale.each { |locale, value| @record.set_translation(field, locale, value) if OpenLoam.locales.include?(locale) }
      end
      redirect_to translate_path, notice: "Translations saved."
    end

    private

    def set_record
      model = OpenLoam::Import.allowed_model(params[:translatable_type]) # whitelist: a OpenLoam entity only
      raise ActiveRecord::RecordNotFound unless model.include?(OpenLoam::Translatable)

      @record = model.find(params[:translatable_id])
      @fields = model.open_loam_translatable_attributes
    end

    def translate_path
      admin_translations_path(translatable_type: @record.class.name, translatable_id: @record.id)
    end
    helper_method :translate_path
  end
end
