module Admin
  # Managed lookup lists (OpenLoam::Dictionary) — manager-only. The index lists a
  # tenant's dictionaries; the edit screen curates a dictionary's entries
  # (Admin::DictionaryEntriesController). Tenant-scoped by the model's default
  # scope, so a manager only ever sees their own tenant's lists.
  class DictionariesController < BaseController
    before_action { require_role!(:manager) }
    before_action :set_dictionary, only: %i[edit update destroy]

    def index
      @dictionaries = OpenLoam::Dictionary.order(:key)
    end

    def new
      @dictionary = OpenLoam::Dictionary.new
    end

    def create
      @dictionary = OpenLoam::Dictionary.new(dictionary_params)
      if @dictionary.save
        redirect_to edit_admin_dictionary_path(@dictionary), notice: "Dictionary created — add its entries below."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @entry = @dictionary.entries.new(active: true)
    end

    def update
      if @dictionary.update(dictionary_params)
        redirect_to admin_dictionaries_path, notice: "Dictionary updated."
      else
        @entry = @dictionary.entries.new
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @dictionary.destroy!
      redirect_to admin_dictionaries_path, notice: "Dictionary deleted."
    end

    private

    def set_dictionary
      @dictionary = OpenLoam::Dictionary.find(params[:id])
    end

    def dictionary_params
      params.require(:dictionary).permit(:key, :name)
    end
  end
end
