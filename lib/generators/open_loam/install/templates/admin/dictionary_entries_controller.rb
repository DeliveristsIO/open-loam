module Admin
  # Entries of a OpenLoam::Dictionary — manager-only, nested under a dictionary.
  # Add / edit (value, label, color, icon, position, default, active) / delete;
  # reordering is by editing `position`.
  class DictionaryEntriesController < BaseController
    before_action { require_role!(:manager) }
    before_action :set_dictionary
    before_action :set_entry, only: %i[update destroy]

    def create
      @entry = @dictionary.entries.new(entry_params)
      if @entry.save
        redirect_to edit_admin_dictionary_path(@dictionary), notice: "Entry added."
      else
        @dictionary_errors = @entry.errors.full_messages
        redirect_to edit_admin_dictionary_path(@dictionary), alert: @dictionary_errors.join(", ")
      end
    end

    def update
      if @entry.update(entry_params)
        redirect_to edit_admin_dictionary_path(@dictionary), notice: "Entry updated."
      else
        redirect_to edit_admin_dictionary_path(@dictionary), alert: @entry.errors.full_messages.join(", ")
      end
    end

    def destroy
      @entry.destroy!
      redirect_to edit_admin_dictionary_path(@dictionary), notice: "Entry removed."
    end

    private

    def set_dictionary
      @dictionary = OpenLoam::Dictionary.find(params[:dictionary_id])
    end

    def set_entry
      @entry = @dictionary.entries.find(params[:id])
    end

    def entry_params
      params.require(:dictionary_entry).permit(:value, :label, :color, :icon, :position, :is_default, :active)
    end
  end
end
