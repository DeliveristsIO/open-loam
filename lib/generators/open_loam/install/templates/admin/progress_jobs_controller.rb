module Admin
  # Long-running task progress (OpenLoam::ProgressJob) — a tenant-scoped list of
  # recent jobs with a live bar (the open_loam.progress.updated SSE event updates it).
  # Your app starts jobs with OpenLoam::Progress.start in its own background jobs;
  # a running one can be cancelled cooperatively here.
  class ProgressJobsController < BaseController
    skip_authorization! "A tenant-scoped list of the tenant's own jobs; cancel is the gated action.",
                        only: :index

    def index
      @jobs = OpenLoam::ProgressJob.recent.limit(20)
    end

    def cancel
      job = OpenLoam::ProgressJob.find(params[:id])
      # Manager-or-owner: a member must not cancel another user's job.
      authorized!
      raise OpenLoam::NotAuthorizedError unless current_role == :manager || job.actor_id == current_actor&.id
      job.cancel! if job.running?
      redirect_to admin_progress_jobs_path, notice: "Job cancelled."
    end
  end
end
