require "json"
require "fileutils"

namespace :open_loam do
  # Score the app's current test suite as a golden-task eval result and record it
  # under ai/benchmark_runs/ (L-303). Run this in a OpenLoam app AFTER an agent (or
  # you) has implemented a golden task:
  #
  #   bin/rails "open_loam:eval[2]"                       # task 2, tests only
  #   bin/rails "open_loam:eval[2,tenancy_leak:unscoped]" # note an invariant breach
  #
  # Exits non-zero if the task did not pass, so it drops straight into CI.
  desc "Score the current test suite as a golden-task eval result (open_loam:eval[task,violation,violation,...])"
  task :eval, [ :task ] => :environment do |_task, args|
    task_id = args[:task] || "unspecified"
    violations = args.extras # any positional args after the task id are violations

    output = `bin/rails test 2>&1`
    summary = OpenLoam::Eval.parse_summary(output)
    card = OpenLoam::Eval.scorecard(task: task_id, summary: summary, violations: violations)

    dir = Rails.root.join("ai", "benchmark_runs")
    FileUtils.mkdir_p(dir)
    stamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
    file = dir.join("eval-#{task_id}-#{stamp}.json")
    File.write(file, JSON.pretty_generate(card))

    puts JSON.pretty_generate(card)
    puts "Recorded #{file}"
    abort("Eval FAILED for task #{task_id}") unless card[:passed]
  end
end
