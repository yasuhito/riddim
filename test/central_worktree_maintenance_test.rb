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
      'GIT_CONFIG_COUNT' => '3', 'GIT_CONFIG_KEY_0' => 'maintenance.autoDetach', 'GIT_CONFIG_VALUE_0' => 'true',
      'GIT_CONFIG_KEY_1' => 'maintenance.auto', 'GIT_CONFIG_VALUE_1' => 'true',
      'GIT_CONFIG_KEY_2' => 'init.defaultBranch', 'GIT_CONFIG_VALUE_2' => 'main', 'GIT_TRACE2_EVENT' => trace
    }
    Bundler.with_unbundled_env do
      Open3.capture2e(environment, RbConfig.ruby, '-rbundler/setup', Gem.bin_path('cucumber', 'cucumber'),
                      'features/start_worktree.feature:44', '--format', 'progress',
                      chdir: File.expand_path('..', __dir__))
    end
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity
  def runtime_maintenance(trace)
    rows = File.readlines(trace).map { |line| JSON.parse(line) }
    commit = rows.find do |row|
      row['event'] == 'start' && row.fetch('argv').last(3) == ['commit', '-qm', 'runtime']
    end
    children = rows.select { |row| row['event'] == 'child_start' && row['sid'] == commit.fetch('sid') }
    children.map { |row| row.fetch('argv') }.find { |argv| argv.include?('maintenance') }
  end

  def test_submodule_source_commit_waits_for_automatic_maintenance
    Dir.mktmpdir('riddim-fixture-maintenance-') do |root|
      trace = File.join(root, 'trace.jsonl')
      output, status = run_submodule_fixture(trace)
      maintenance = runtime_maintenance(trace)

      assert_equal [true, true, true],
                   [status.success?, output.include?('1 scenario (1 passed)'), maintenance&.include?('--no-detach')],
                   "#{output}\nsource maintenance: #{maintenance.inspect}"
    end
  end
end
