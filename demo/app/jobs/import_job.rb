# Runs a CSV import in the background, advancing a OpenLoam::ProgressJob so the admin
# watches it live (L-915). Carries tenant + actor explicitly, like every OpenLoam job.
# The per-row summary (created/updated/failed + error rows) is stored on the
# ProgressJob's `result` for the summary screen.
#
# The file arrives as a blob id, never as a job argument. ActiveJob arguments are
# serialized into the queue backend and echoed in the job log, so passing the CSV
# itself would persist every row — including columns bound for encrypted fields —
# in the clear, outside the encryption the destination columns exist to provide.
class ImportJob < ApplicationJob
  queue_as :default

  def perform(entity_type:, blob_id:, mapping:, match_key:, tenant_id:, actor_id:)
    tenant = OpenLoam::Tenant.find(tenant_id)
    actor = User.find_by(id: actor_id)
    model = OpenLoam::Import.allowed_model(entity_type)
    blob = ActiveStorage::Blob.find_by(id: blob_id)
    return if blob.nil? # already purged: nothing to import, not an error

    csv = blob.download.force_encoding("UTF-8")

    OpenLoam.as_tenant(tenant, actor: actor) do
      total = [ CSV.parse(csv).size - 1, 0 ].max
      progress = OpenLoam::Progress.start(name: "Import #{entity_type}", total: total)
      begin
        result = OpenLoam::Import.run(csv, model: model, mapping: mapping, actor: actor, match_key: match_key, progress: progress)
        progress.update_columns(result: result.to_h)
        progress.complete!
      rescue StandardError => error
        progress.fail!(error.message)
      end
    end
  ensure
    # The upload has done its job; leaving it behind is a second copy of the
    # same data with none of the destination's protections.
    blob&.purge_later
  end
end
