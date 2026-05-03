# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

default_tasks = %i[test]

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
  default_tasks << :rubocop
rescue LoadError
  # rubocop not installed; skip
end

task default: default_tasks
