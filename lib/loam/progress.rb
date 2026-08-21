module Loam
  # Entry point for progress tracking. Start a job, then drive it through the
  # returned Loam::ProgressJob:
  #
  #   progress = Loam::Progress.start(name: "Reindex", total: equipment.count)
  #   equipment.find_each do |record|
  #     break if progress.cancelled?   # cooperative cancel
  #     do_work(record)
  #     progress.advance                # throttled SSE push
  #   end
  #   progress.complete!
  #
  # The job is created in the current tenant (and stamped with the current
  # actor), so it is only visible and streamable there. In a background job,
  # establish the tenant with Loam.as_tenant first, like the webhook/digest jobs.
  module Progress
    module_function

    def start(name:, total:, key: nil)
      Loam::ProgressJob.create!(
        key: key,
        name: name,
        total: total.to_i,
        completed: 0,
        status: "running",
        actor_id: Loam.actor&.id,
        started_at: Time.current
      )
    end
  end
end
