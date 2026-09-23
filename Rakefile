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

desc 'Check the PlusCal ownership models (requires mise Java and tla2tools.jar)'
task :model do
  jar = File.join(Dir.home, '.local/share/tlaplus/v1.7.4/tla2tools.jar')
  abort "Missing #{jar}; see spec/README.md" unless File.file?(jar)

  java = ['mise', 'exec', 'java@temurin-21.0.12+8.0.LTS', '--', 'java', '-cp', jar]
  Dir.chdir('spec') do
    %w[ClaimOneName ProtectNewGeneration].each do |name|
      sh(*java, 'pcal.trans', "#{name}.tla")
      sh(*java, 'tlc2.TLC', '-workers', '1', "#{name}.tla")
    end
  end
end

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
