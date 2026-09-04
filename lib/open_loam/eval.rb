module OpenLoam
  # Scripted evaluation scoring for the golden tasks (L-303). An agent (or a
  # human) implements a task against a fresh OpenLoam app; this scores the RESULT
  # consistently — the test outcome plus the structural invariants — into a
  # machine-readable scorecard, so runs are comparable over time
  # (ai/benchmark_runs/). Driving the agent is out of scope; consistent scoring
  # is the point, and it encodes the golden-tasks bar: green suite AND no
  # invariant violated.
  module Eval
    # The minitest summary line, whatever the counts: "N runs, M assertions,
    # F failures, E errors, S skips".
    SUMMARY = /(\d+)\s+runs?,\s+(\d+)\s+assertions?,\s+(\d+)\s+failures?,\s+(\d+)\s+errors?/

    module_function

    def parse_summary(output)
      match = output.to_s.match(SUMMARY)
      return nil unless match

      { runs: match[1].to_i, assertions: match[2].to_i, failures: match[3].to_i, errors: match[4].to_i }
    end

    # A task PASSES only when the suite is green AND no invariant was violated —
    # the bar the golden-tasks doc sets. `violations` is a list of invariant
    # breaches a reviewer (or a lint) found (tenancy leak, unauthorized write, …);
    # `interventions` counts human corrections needed. Both feed the comparison,
    # neither is inferred here.
    def scorecard(task:, summary:, violations: [], interventions: 0, notes: nil)
      counts = summary || { runs: 0, assertions: 0, failures: 0, errors: 0 }
      green = counts[:failures].to_i.zero? && counts[:errors].to_i.zero? && counts[:runs].to_i.positive?
      passed = green && Array(violations).empty?

      {
        task: task.to_s,
        passed: passed,
        tests_green: green,
        runs: counts[:runs].to_i,
        assertions: counts[:assertions].to_i,
        failures: counts[:failures].to_i,
        errors: counts[:errors].to_i,
        violations: Array(violations),
        interventions: interventions.to_i,
        notes: notes
      }
    end
  end
end
