# A demo of live progress: advance a OpenLoam::ProgressJob over the tenant's
# Equipment so the admin's Tasks screen fills its bar over SSE. The small sleep
# is DEMO-ONLY (it makes the bar watchable) — real work would replace it. Runs in
# the background (ActiveJob), carrying the tenant + actor explicitly.
class DemoProgressJob < ApplicationJob
  queue_as :default

  def perform(tenant_id:, actor_id:)
    tenant = OpenLoam::Tenant.find(tenant_id)
    actor = User.find_by(id: actor_id)

    OpenLoam.as_tenant(tenant, actor: actor) do
      records = Equipment.all.to_a
      progress = OpenLoam::Progress.start(name: "Touch all equipment", total: records.size)

      records.each do |equipment|
        break if progress.cancelled?  # cooperative cancel
        sleep 0.4                     # DEMO ONLY — stand-in for real per-record work
        equipment.touch
        progress.advance(message: "Processed #{equipment.name}")
      end

      progress.complete! unless progress.cancelled?
    end
  end
end
