# build / install / release. `rake release` is what rubygems/release-gem runs
# in the publish workflow; because that workflow is triggered BY the version
# tag, the tagging step is a no-op and only the gem push happens.
require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
  t.verbose = false
  t.warning = false
end

desc "Run the Loam generator harness (static template checks + a real Rails app smoke test)"
task default: :test

# Cutting a release touches two files that must move together: the version
# constant, and demo/Gemfile.lock, which records the path gem BY VERSION. CI
# bundles the demo frozen, so a bump without the lock refresh fails the demo
# job with a bare `exit 16` — and because the tag is pushed in the same breath
# as the commit, CI cannot repair the commit the tag points at. Hence a task
# rather than a checklist item.
desc "Bump the gem version and refresh the demo lockfile (rake bump[0.2.0])"
task :bump, [:version] do |_, args|
  version = args[:version]
  abort "usage: rake bump[0.2.0]" if version.nil? || version.empty?
  abort "#{version.inspect} is not a MAJOR.MINOR.PATCH version" unless version.match?(/\A\d+\.\d+\.\d+\z/)

  path = "lib/loam/version.rb"
  source = File.read(path)
  current = source[/VERSION = "([^"]+)"/, 1]
  abort "already at #{version}" if current == version

  File.write(path, source.sub(/VERSION = "[^"]+"/, %(VERSION = "#{version}")))
  puts "#{path}: #{current} -> #{version}"

  # Unbundled: rake may itself be running under this repo's bundle, and the
  # demo resolves against its own Gemfile.
  Bundler.with_unbundled_env do
    Dir.chdir("demo") { sh "bundle install --quiet" }
  end
  puts "demo/Gemfile.lock refreshed"

  puts <<~NEXT

    Next:
      1. add the #{version} entry to CHANGELOG.md
      2. git add lib/loam/version.rb CHANGELOG.md demo/Gemfile.lock
      3. git commit -m "chore(release): #{version}"
      4. git tag -a v#{version} -m "Loam #{version}" && git push --follow-tags
  NEXT
end
