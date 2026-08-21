module Admin
  # Long-running task progress (Loam::ProgressJob) — a tenant-scoped list of
  # recent jobs with a live bar (the loam.progress.updated SSE event updates it).
  # Your app starts jobs with Loam::Progress.start in its own background jobs;
  # a running one can be cancelled cooperatively here.
  class ProgressJobsController < BaseController
    def index
      @jobs = Loam::ProgressJob.recent.limit(20)
    end

    def cancel
      job = Loam::ProgressJob.find(params[:id])
      # Manager-or-owner: a member must not cancel another user's job.
      raise Loam::NotAuthorizedError unless current_role == :manager || job.actor_id == current_actor&.id
      job.cancel! if job.running?
      redirect_to admin_progress_jobs_path, notice: "Job cancelled."
    end
  end
end
