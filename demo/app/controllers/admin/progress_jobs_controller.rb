module Admin
  # Long-running task progress (Loam::ProgressJob). A tenant-scoped list of recent
  # jobs with a live bar (the loam.progress.updated SSE event updates it). Any
  # member can watch; "Run a demo job" enqueues DemoProgressJob, and a running
  # job can be cancelled cooperatively.
  class ProgressJobsController < BaseController
    def index
      @jobs = Loam::ProgressJob.recent.limit(20)
    end

    def run
      DemoProgressJob.perform_later(tenant_id: current_tenant.id, actor_id: current_actor.id)
      redirect_to admin_progress_jobs_path, notice: "Demo job started — watch it progress live."
    end

    def cancel
      job = Loam::ProgressJob.find(params[:id])
      job.cancel! if job.running?
      redirect_to admin_progress_jobs_path, notice: "Job cancelled."
    end
  end
end
