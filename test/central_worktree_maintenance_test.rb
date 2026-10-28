# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'json'
require 'open3'
require 'tmpdir'

# Local-clone fixtures must not race their source's detached automatic repack.
class CentralWorktreeMaintenanceTest < Minitest::Test
  # rubocop:disable-next Metrics/MethodLength
  def run_submodule_fixture(trace)
    environment = {
      'GIT_CONFIG_GLOBAL' => File::NULL, 'GIT_CONFIG_NOSYSTEM' => '1',
      'GIT_CONFIG_COUNT' => '6', 'GIT_CONFIG_KEY_0' => 'maintenance.autoDetach', 'GIT_CONFIG_VALUE_0' => 'true',
      'GIT_CONFIG_KEY_1' => 'maintenance.auto', 'GIT_CONFIG_VALUE_1' => 'true',
      'GIT_CONFIG_KEY_2' => 'init.defaultBranch', 'GIT_CONFIG_VALUE_2' => 'main',
      'GIT_CONFIG_KEY_3' => 'gc.auto', 'GIT_CONFIG_VALUE_3' => '1',
      'GIT_CONFIG_KEY_4' => 'gc.autoDetach', 'GIT_CONFIG_VALUE_4' => 'true',
      'GIT_CONFIG_KEY_5' => 'maintenance.strategy', 'GIT_CONFIG_VALUE_5' => 'gc', 'GIT_TRACE2_EVENT' => trace
    }
    Bundler.with_unbundled_env do
      Open3.capture2e(environment, RbConfig.ruby, '-rbundler/setup', Gem.bin_path('cucumber', 'cucumber'),
                      'features/start_worktree.feature:44', '--format', 'progress',
                      chdir: File.expand_path('..', __dir__))
    end
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def runtime_maintenance(trace)
    rows = File.readlines(trace).map { |line| JSON.parse(line) }
    commit = rows.find do |row|
      row['event'] == 'start' && row.fetch('argv').last(3) == ['commit', '-qm', 'runtime']
    end
    commit_exit = rows.find { |row| row['event'] == 'exit' && row['sid'] == commit.fetch('sid') }
    repacks = rows.select do |row|
      row['event'] == 'start' && row['sid'].start_with?("#{commit.fetch('sid')}/") && row.fetch('argv')[1] == 'repack'
    end
    completed = repacks.all? do |repack|
      finish = rows.find { |row| row['event'] == 'exit' && row['sid'] == repack.fetch('sid') }
      finish && finish['code'].zero? && finish.fetch('time') <= commit_exit.fetch('time')
    end
    { repacks: repacks.length, completed_before_commit: completed }
  end

  def test_submodule_source_commit_waits_for_automatic_maintenance
    Dir.mktmpdir('riddim-fixture-maintenance-') do |root|
      trace = File.join(root, 'trace.jsonl')
      output, status = run_submodule_fixture(trace)
      maintenance = runtime_maintenance(trace)

      assert_equal [true, true, true, true],
                   [status.success?, output.include?('1 scenario (1 passed)'),
                    maintenance.fetch(:repacks).positive?, maintenance.fetch(:completed_before_commit)],
                   "#{output}\nsource maintenance: #{maintenance.inspect}"
    end
  end
end
