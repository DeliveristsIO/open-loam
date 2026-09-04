module OpenLoam
  # Entry point for progress tracking. Start a job, then drive it through the
  # returned OpenLoam::ProgressJob:
  #
  #   progress = OpenLoam::Progress.start(name: "Reindex", total: equipment.count)
  #   equipment.find_each do |record|
  #     break if progress.cancelled?   # cooperative cancel
  #     do_work(record)
  #     progress.advance                # throttled SSE push
  #   end
  #   progress.complete!
  #
  # The job is created in the current tenant (and stamped with the current
  # actor), so it is only visible and streamable there. In a background job,
  # establish the tenant with OpenLoam.as_tenant first, like the webhook/digest jobs.
  module Progress
    module_function

    def start(name:, total:, key: nil)
      OpenLoam::ProgressJob.create!(
        key: key,
        name: name,
        total: total.to_i,
        completed: 0,
        status: "running",
        actor_id: OpenLoam.actor&.id,
        started_at: Time.current
      )
    end
  end
end
