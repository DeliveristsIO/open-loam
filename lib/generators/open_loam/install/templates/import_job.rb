# Runs a CSV import in the background, advancing a Loam::ProgressJob so the admin
# watches it live (L-915). Carries tenant + actor explicitly, like every Loam job.
# The per-row summary (created/updated/failed + error rows) is stored on the
# ProgressJob's `result` for the summary screen.
class ImportJob < ApplicationJob
  queue_as :default

  def perform(entity_type:, csv:, mapping:, match_key:, tenant_id:, actor_id:)
    tenant = Loam::Tenant.find(tenant_id)
    actor = User.find_by(id: actor_id)
    model = Loam::Import.allowed_model(entity_type)

    Loam.as_tenant(tenant, actor: actor) do
      total = [ CSV.parse(csv).size - 1, 0 ].max
      progress = Loam::Progress.start(name: "Import #{entity_type}", total: total)
      begin
        result = Loam::Import.run(csv, model: model, mapping: mapping, actor: actor, match_key: match_key, progress: progress)
        progress.update_columns(result: result.to_h)
        progress.complete!
      rescue StandardError => error
        progress.fail!(error.message)
      end
    end
  end
end
