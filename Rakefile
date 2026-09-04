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
