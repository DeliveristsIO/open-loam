module Admin
  # Long-running task progress (OpenLoam::ProgressJob). A tenant-scoped list of recent
  # jobs with a live bar (the open_loam.progress.updated SSE event updates it). Any
  # member can watch; "Run a demo job" enqueues DemoProgressJob, and a running
  # job can be cancelled cooperatively.
  class ProgressJobsController < BaseController
    def index
      @jobs = OpenLoam::ProgressJob.recent.limit(20)
    end

    def run
      DemoProgressJob.perform_later(tenant_id: current_tenant.id, actor_id: current_actor.id)
      redirect_to admin_progress_jobs_path, notice: "Demo job started — watch it progress live."
    end

    def cancel
      job = OpenLoam::ProgressJob.find(params[:id])
      # Manager-or-owner: a member must not cancel another user's job.
      raise OpenLoam::NotAuthorizedError unless current_role == :manager || job.actor_id == current_actor&.id
      job.cancel! if job.running?
      redirect_to admin_progress_jobs_path, notice: "Job cancelled."
    end
  end
end
