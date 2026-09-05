module Admin
  # Generic CSV importer, scoped by entity_type — manager-only (a privileged bulk
  # mutation). Flow: new (upload) → preview (map columns) → create (dry-run
  # summary, or a backgrounded run reporting live progress). The mapping only
  # offers fields the manager may write (OpenLoam::Import.allowed_targets); a crafted
  # target is refused by the engine.
  class ImportsController < BaseController
    before_action { require_role!(:manager) }
    before_action :set_model, only: %i[preview create]

    def new
      @entity_type = params[:entity_type]
    end

    # Parse the uploaded file, show the mapping form + a few sample rows.
    def preview
      @csv = read_upload
      preview = OpenLoam::Import.preview(@csv)
      @headers = preview[:headers]
      @sample = preview[:rows]
      @targets = OpenLoam::Import.allowed_targets(@model, current_actor).to_a.sort
    rescue OpenLoam::Error => error
      redirect_to new_admin_import_path(entity_type: @entity_type), alert: error.message
    end

    def create
      @csv = params[:csv].to_s
      mapping = params[:mapping].to_unsafe_h.reject { |_h, target| target.blank? }
      match_key = params[:match_key].presence

      if params[:commit] == "Dry run"
        run_dry(mapping, match_key)
      else
        ImportJob.perform_later(entity_type: @entity_type, blob_id: staged_csv_blob(@csv).id, mapping: mapping,
                                match_key: match_key, tenant_id: current_tenant.id, actor_id: current_actor.id)
        redirect_to admin_progress_jobs_path, notice: "Import started — watch it progress under Tasks."
      end
    rescue OpenLoam::Error => error
      redirect_to new_admin_import_path(entity_type: @entity_type), alert: error.message
    end

    # The failed rows as a fix-and-re-upload CSV.
    def download_errors
      @entity_type = params[:entity_type]
      model = OpenLoam::Import.allowed_model(@entity_type)
      csv = params[:csv].to_s
      mapping = params[:mapping].to_unsafe_h.reject { |_h, target| target.blank? }
      result = OpenLoam::Import.run(csv, model: model, mapping: mapping, actor: current_actor,
                                match_key: params[:match_key].presence, dry_run: true)
      send_data OpenLoam::Import.error_csv(result, csv),
                filename: "#{@entity_type.underscore}-import-errors.csv", type: "text/csv"
    end

    private

    def set_model
      @entity_type = params[:entity_type]
      @model = OpenLoam::Import.allowed_model(@entity_type)
    end

    def run_dry(mapping, match_key)
      @result = OpenLoam::Import.run(@csv, model: @model, mapping: mapping, actor: current_actor,
                                 match_key: match_key, dry_run: true)
      @headers = OpenLoam::Import.preview(@csv)[:headers]
      render :summary
    end

    def read_upload
      file = params[:file]
      raise OpenLoam::Error, "choose a CSV file to upload" if file.blank?

      file.read.force_encoding("UTF-8")
    end

    # The CSV goes to blob storage and the JOB gets an id. ActiveJob arguments
    # are serialized into the queue backend and echoed in the job log, so
    # passing the file itself would leave every row sitting in the clear —
    # including the columns headed for encrypted fields. ImportJob purges it.
    def staged_csv_blob(csv)
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(csv),
        filename: "#{@entity_type.underscore}-import-#{SecureRandom.hex(8)}.csv",
        content_type: "text/csv"
      )
    end
  end
end
