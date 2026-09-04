require "test_helper"

# L-303: consistent scoring of a golden-task attempt. parse_summary reads the
# minitest tally; scorecard applies the golden-tasks bar (green suite AND no
# invariant violated).
class OpenLoamEvalTest < ActiveSupport::TestCase
  test "parse_summary reads the minitest tally" do
    out = "Finished in 5s\n440 runs, 1497 assertions, 0 failures, 0 errors, 0 skips"
    assert_equal({ runs: 440, assertions: 1497, failures: 0, errors: 0 }, OpenLoam::Eval.parse_summary(out))
  end

  test "parse_summary returns nil when there is no tally" do
    assert_nil OpenLoam::Eval.parse_summary("boom: the suite crashed before running")
  end

  test "a green suite with no violations passes" do
    card = OpenLoam::Eval.scorecard(task: "2", summary: { runs: 10, assertions: 30, failures: 0, errors: 0 })
    assert card[:passed]
    assert card[:tests_green]
  end

  test "any failure or error fails the task" do
    refute OpenLoam::Eval.scorecard(task: "2", summary: { runs: 10, assertions: 30, failures: 1, errors: 0 })[:passed]
    refute OpenLoam::Eval.scorecard(task: "2", summary: { runs: 10, assertions: 30, failures: 0, errors: 2 })[:passed]
  end

  test "a green suite still FAILS if an invariant was violated" do
    card = OpenLoam::Eval.scorecard(task: "2", summary: { runs: 10, assertions: 30, failures: 0, errors: 0 },
                                violations: [ "cross-tenant read in ReportsController" ])
    refute card[:passed]
    assert card[:tests_green], "the suite was green — but a violation still fails the task"
    assert_equal 1, card[:violations].size
  end

  test "no tests run is not a pass" do
    refute OpenLoam::Eval.scorecard(task: "2", summary: nil)[:passed]
  end
end
