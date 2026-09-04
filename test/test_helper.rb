require "minitest/autorun"
require "bundler"
require "open3"
require "tmpdir"
require "fileutils"
require "set"
require "shellwords"

# Everything this harness reads — generator templates, generated Rails files,
# captured stdout — is UTF-8, and it is matched against UTF-8 literals in these
# test files. Ruby picks the external encoding from the locale, so a shell with
# no LANG set (a bare CI container, `env -i`) makes all of it US-ASCII and every
# em dash becomes an "invalid byte sequence" error far from its cause. The
# harness declares its own encoding rather than depending on the caller's.
Encoding.default_external = Encoding::UTF_8

# Support code for the OpenLoam generator harness.
#
# The harness shells out a lot: it builds a real Rails app in a temp directory
# and drives the real generators through it. Everything about running those
# commands correctly lives here, because every one of them has the same three
# hazards: a leaked Bundler environment, a generator that blocks on stdin, and
# a failure whose output you cannot see.
module OpenLoamHarness
  GEM_ROOT = File.expand_path("..", __dir__)

  # Where generated apps go. OPEN_LOAM_HARNESS_SCRATCH lets a caller put the
  # artifacts somewhere it will go looking for them; otherwise the system temp
  # dir. This used to hardcode one machine's session scratchpad, which meant
  # nothing on any other machine and silently fell back anyway.
  SCRATCH_ROOT = begin
    preferred = ENV["OPEN_LOAM_HARNESS_SCRATCH"]
    preferred && File.directory?(preferred) && File.writable?(preferred) ? preferred : Dir.tmpdir
  end

  # The flags the demo app was built with: no git, no deploy tooling, no
  # frontend, SQLite default. --skip-bundle matters — the open_loam path gem has to
  # be in the Gemfile before anything bundles, so we bundle exactly once.
  RAILS_NEW_FLAGS = %w[
    --skip-git --skip-kamal --skip-ci --skip-docker --skip-solid
    --skip-action-mailbox --skip-action-text --skip-hotwire --skip-jbuilder
    --skip-bootsnap --skip-brakeman --skip-rubocop --skip-bundle
  ].freeze

  # One shelled-out command and everything needed to explain its failure.
  Result = Struct.new(:label, :command, :dir, :output, :exitstatus, :seconds, keyword_init: true) do
    def ok? = exitstatus.zero?

    def timed_out? = exitstatus == 124

    # What gets printed when an assertion on this command fails. The captured
    # stdout/stderr is the whole point — a bare "expected 0, got 1" from a
    # generator run is useless.
    def failure_report
      [
        "",
        "#{label} failed (exit #{exitstatus}#{' — TIMED OUT' if timed_out?})",
        "  $ #{command}",
        "  in #{dir}",
        "--- captured stdout+stderr ---",
        output.to_s.empty? ? "(no output)" : output,
        "--- end output ---",
        ""
      ].join("\n")
    end
  end

  class << self
    # Every generated app path we have handed out, so the at_exit hook can
    # clean up the ones belonging to a green run.
    def app_dirs = @app_dirs ||= []

    # Set when any step fails, so we keep the evidence instead of deleting it.
    def keep! = @keep = true

    def keep? = @keep == true

    # Run a command in +dir+ and capture everything.
    #
    # Three deliberate choices:
    #   * Bundler.with_unbundled_env — without it BUNDLE_GEMFILE from whatever
    #     invoked rake leaks into `rails new` and into the generated app, and
    #     the app resolves against the wrong Gemfile.
    #   * stdin_data: "" — generators prompt on file collisions. With an
    #     inherited tty that blocks forever in an unattended run; with an
    #     immediately-closed stdin it cannot.
    #   * the `timeout` utility rather than Ruby's Timeout — it kills the whole
    #     child process group, so a hung `rails` does not outlive the harness.
    #     A timeout surfaces as exit 124, i.e. as an ordinary failure.
    def run(label, command, dir:, timeout: 300)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      argv = ["timeout", "-k", "5", timeout.to_s, "bash", "-c", command]

      output, status = Bundler.with_unbundled_env do
        Open3.capture2e(*argv, chdir: dir, stdin_data: "")
      end

      Result.new(
        label: label, command: command, dir: dir, output: output,
        exitstatus: status.exitstatus || 1,
        seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      )
    end

    # Generate a fresh Rails app wired to the local open_loam gem, and return its
    # path plus the steps it took to get there. Slow-ish, so callers do this
    # once and assert against the result many times.
    #
    # +extra_flags+ lets a test build a deliberately unusual app — an app
    # generated with --skip-test, say — without duplicating the flag list.
    def build_app(name: "open_loam_harness_app", extra_flags: [])
      parent = Dir.mktmpdir("open_loam-harness-", SCRATCH_ROOT)
      app_dirs << parent
      app = File.join(parent, name)
      flags = (RAILS_NEW_FLAGS + extra_flags).join(" ")

      new_app = run("rails new #{name}", "rails new #{name} #{flags}", dir: parent, timeout: 300)
      return [app, [new_app]] unless new_app.ok?

      File.open(File.join(app, "Gemfile"), "a") do |f|
        f.puts %(gem "open-loam", path: "#{GEM_ROOT}")
      end

      bundle = run("bundle install", "bundle install", dir: app, timeout: 600)
      [app, [new_app, bundle]]
    end

    def report_timeline(steps, label: nil)
      return if steps.empty?

      puts "\nHarness steps#{" — #{label}" if label}:"
      steps.each { |s| puts format("  %-42s %6.1fs  exit %d", s.label, s.seconds, s.exitstatus) }
      puts format("  %-42s %6.1fs", "TOTAL", steps.sum(&:seconds))
    end
  end
end

# Base class for every test that drives a real generated Rails app. It owns the
# two things all of them need: a step that fails with the command's own output
# attached, and a timeline so a green run still shows where the time went.
class HarnessCase < Minitest::Test
  def setup
    @steps = []
  end

  def teardown
    # Keep the generated tree only when something actually failed. Some steps
    # tolerate a non-zero exit, so a failing command is not by itself a reason
    # to leave an app behind.
    OpenLoamHarness.keep! unless passed?
    OpenLoamHarness.report_timeline(@steps, label: name)
  end

  private

  # Run a command in the app and assert it succeeded, with its captured
  # stdout+stderr in the failure message.
  def step(label, command, dir, timeout: 180)
    result = record(OpenLoamHarness.run(label, command, dir: dir, timeout: timeout))
    assert result.ok?, result.failure_report
    result
  end

  # Run a command whose exit status is not itself the assertion — the caller
  # checks the state it left behind.
  def attempt(label, command, dir, timeout: 180)
    record(OpenLoamHarness.run(label, command, dir: dir, timeout: timeout))
  end

  def record(result)
    @steps << result
    result
  end

  # Build an app and assert it built. Returns its path.
  def build_app(**options)
    app, steps = OpenLoamHarness.build_app(**options)
    steps.each { |s| assert record(s).ok?, s.failure_report }
    app
  end

  # Evaluate Ruby inside the generated app, so assertions can be made about
  # real records rather than about files. Going through the app's own boot is
  # the point: it loads config/initializers/open_loam.rb the way a real process
  # would.
  def runner(label, ruby, app, timeout: 180)
    step(label, "bin/rails runner #{Shellwords.escape(ruby)}", app, timeout: timeout).output.strip
  end

  # Anything that shares a terminal with a Rails boot can write to it —
  # deprecation notices, a version manager, a logger. So a value read back out
  # of the app is fenced with a sentinel rather than scraped off stdout, which
  # would otherwise turn unrelated noise into a baffling parse error.
  VALUE_SENTINEL = "OPEN_LOAM_HARNESS_VALUE".freeze

  def runner_integer(label, expression, app)
    output = runner(label, %(print "#{VALUE_SENTINEL}=#{'#{'}#{expression}#{'}'}"), app)
    match = output.match(/#{VALUE_SENTINEL}=(-?\d+)\b/)

    assert match, "expected an integer from `#{expression}` in the generated app, got:\n#{output}"
    Integer(match[1])
  end

  # Minitest's own tally line, pulled out of a generated app's test output so a
  # green run still reports how much it actually ran.
  def summary_line(output)
    output.lines.reverse.find { |l| l.match?(/\d+ runs?, .*assertions?/) }&.strip || "(no summary line found)"
  end
end

# Keep the generated app when something failed (its logs and its half-written
# files are the evidence); delete it when the run was green.
Minitest.after_run do
  dirs = OpenLoamHarness.app_dirs
  next if dirs.empty?

  if OpenLoamHarness.keep?
    puts "\nGenerated app kept for inspection:"
    dirs.each { |d| puts "  #{d}" }
  else
    dirs.each { |d| FileUtils.remove_entry(d) if File.directory?(d) }
  end
end
