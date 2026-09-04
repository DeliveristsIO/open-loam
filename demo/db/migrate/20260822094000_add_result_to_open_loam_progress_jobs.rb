class AddResultToLoamProgressJobs < ActiveRecord::Migration[8.1]
  def change
    # A structured result for a finished job (e.g. an import summary + error rows).
    add_column :loam_progress_jobs, :result, :json
  end
end
