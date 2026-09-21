# frozen_string_literal: true

require 'cucumber/rake/task'
require 'rake/testtask'
require 'rubocop/rake_task'
require_relative 'test/support/one_then_per_scenario'

Rake::TestTask.new(:unit) do |task|
  task.pattern = 'test/**/*_test.rb'
end

Cucumber::Rake::Task.new(:features)

RuboCop::RakeTask.new(:rubocop)

desc 'Check Gherkin conventions'
task :gherkin do
  violations = Dir['features/**/*.feature'].flat_map do |path|
    OneThenPerScenario.call(File.read(path), path: path)
  end
  abort violations.join("\n") unless violations.empty?
end

task test: %i[unit features]
task lint: %i[rubocop gherkin]
task default: %i[test lint]
