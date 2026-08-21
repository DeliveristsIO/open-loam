module Admin
  # Recurring schedules (Loam::ScheduledJob) — manager-only. List/create/edit/
  # delete a tenant's schedules, toggle active, and "run now". The runner
  # (`loam:scheduler:tick`, wired to system cron) is what fires them on schedule.
  class ScheduledJobsController < BaseController
    before_action { require_role!(:manager) }
    before_action :set_job, only: %i[edit update destroy run_now]

    def index
      @jobs = Loam::ScheduledJob.order(:key)
    end

    def new
      @job = Loam::ScheduledJob.new(scope: "tenant", active: true, schedule: "0 3 * * *")
    end

    def create
      @job = Loam::ScheduledJob.new(job_params)
      @job.next_run_at ||= safe_next_run(@job)
      if @job.save
        redirect_to admin_scheduled_jobs_path, notice: "Schedule created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      @job.assign_attributes(job_params)
      @job.next_run_at = safe_next_run(@job) if @job.schedule_changed? || @job.timezone_changed?
      if @job.save
        redirect_to admin_scheduled_jobs_path, notice: "Schedule updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @job.destroy!
      redirect_to admin_scheduled_jobs_path, notice: "Schedule deleted."
    end

    def run_now
      Loam::Scheduler.run_now(@job)
      redirect_to admin_scheduled_jobs_path, notice: "#{@job.name} enqueued."
    end

    private

    def set_job
      @job = Loam::ScheduledJob.find(params[:id])
    end

    def job_params
      params.require(:scheduled_job).permit(:key, :name, :job_class, :schedule, :timezone, :scope, :active)
    end

    # A malformed cron shouldn't 500 — let validation surface it instead.
    def safe_next_run(job)
      job.compute_next_run
    rescue ArgumentError
      nil
    end
  end
end
