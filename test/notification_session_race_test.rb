# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require_relative 'support/notification_worker_fixture'

# A fake Pi lifecycle drives the real extension and real watcher subprocesses.
# The separately tested real Pi RPC path verifies the provider-facing queue.
class NotificationSessionRaceTest < Minitest::Test
  include NotificationWorkerFixture

  GEN = 's1767200000.4242.7'

  def test_late_predecessor_rejection_cannot_claim_successor_or_lose_later_report
    run_scenario('notification_session_race.mjs', expected: ["worker.#{GEN}.1", "worker.#{GEN}.2"])
  end

  def test_unsettled_follow_up_times_out_and_can_be_rearmed
    run_scenario('notification_delivery_timeout.mjs', expected: ["worker.#{GEN}.1"])
  end

  def test_replaced_home_cannot_claim_old_watch_as_ready
    run_scenario('notification_home_replacement.mjs', expected: [])
  end

  def test_pending_report_stays_with_replaced_home
    run_scenario('notification_pending_home_replacement.mjs', expected: [])
  end

  def test_delivery_keeps_source_identity_when_home_changes_at_acceptance
    run_scenario('notification_delivery_home_replacement.mjs', expected: [])
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Minitest/MultipleAssertions
  def test_watcher_scan_stays_with_held_home_after_path_replacement
    Dir.mktmpdir('riddim-scan-race-') do |root|
      state = File.join(root, 'state')
      replacement = File.join(root, 'replacement')
      [state, replacement].each do |path|
        FileUtils.mkdir_p(path)
        write_notification_worker(path, GEN)
        File.write(File.join(path, "worker.#{GEN}.status"), "blocked [at=1]: claim\n", perm: 0o600)
      end
      env = { 'RIDDIM_STATE_DIR' => state, 'RIDDIM_REPLACED_HOME' => state,
              'RIDDIM_REPLACEMENT_HOME' => replacement,
              'RUBYOPT' => "-r#{File.expand_path('support/watch_scan_replacement', __dir__)}" }
      _output, error, result = Bundler.with_unbundled_env do
        Open3.capture3(env, File.expand_path('../bin/riddim', __dir__),
                       'watch-notifications', '--nonce', '0' * 32, '--exclude-stdin', stdin_data: '[]')
      end

      refute_predicate result, :success?, error
      assert File.directory?("#{state}-old"), "old home missing after swap: #{error}"
      refute_path_exists File.join(state, '.notifications'),
                         'replacement home must remain untouched by the watcher scan'
      pending, scan_error, scan_status = Bundler.with_unbundled_env do
        Open3.capture3({ 'RIDDIM_STATE_DIR' => "#{state}-old" }, File.expand_path('../bin/riddim', __dir__),
                       'notifications', 'scan')
      end

      assert_predicate scan_status, :success?, scan_error
      assert_equal(["worker.#{GEN}.1"], JSON.parse(pending).map { |entry| entry.fetch('id') })
    end
  end

  def test_replaced_lock_marker_cannot_claim_old_watch_as_ready
    run_scenario('notification_home_replacement.mjs', expected: [], marker: 'RIDDIM_REPLACE_LOCK')
  end

  def test_corrupt_lock_marker_cannot_claim_old_watch_as_ready
    run_scenario('notification_home_replacement.mjs', expected: [], marker: 'RIDDIM_CORRUPT_LOCK')
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def run_scenario(script, expected:, marker: nil)
    Dir.mktmpdir('riddim-session-race-') do |root|
      state = File.join(root, 'state')
      FileUtils.mkdir_p(state)
      status_path = File.join(state, "worker.#{GEN}.status")
      File.write(status_path, '', perm: 0o600)
      write_notification_worker(state, GEN)
      env = { 'RIDDIM_STATE_DIR' => state, 'RIDDIM_STATUS_PATH' => status_path,
              'RIDDIM_FIRST_ID' => "worker.#{GEN}.1",
              'RIDDIM_EXTENSION' => File.expand_path('../.pi/extensions/riddim-notifications.ts', __dir__) }
      env[marker] = '1' if marker
      output, error, result = Bundler.with_unbundled_env do
        Open3.capture3(env, 'node', File.expand_path("support/#{script}", __dir__))
      end

      assert_predicate result, :success?, "#{output}\n#{error}"
      pending, scan_error, scan_status = Bundler.with_unbundled_env do
        Open3.capture3({ 'RIDDIM_STATE_DIR' => state }, File.expand_path('../bin/riddim', __dir__),
                       'notifications', 'scan')
      end

      assert_predicate scan_status, :success?, scan_error
      assert_equal(expected, JSON.parse(pending).map { |entry| entry.fetch('id') })
    end
  end
end
