# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'tmpdir'
require 'open3'
require_relative '../lib/riddim/notifications'
require_relative 'support/notification_worker_fixture'

class WatcherHistoryTest < Minitest::Test
  include NotificationWorkerFixture

  GEN = 's1767200000.4242.7'

  def test_retained_history_with_slow_record_io_keeps_observer_progress_visible
    run_history('slow')
  end

  def test_slow_scan_after_readiness_does_not_exhaust_recovery
    run_history('post-ready')
  end

  def test_blocked_read_is_not_progress_and_recovers_without_losing_reports
    run_history('hung')
  end

  def test_processing_error_after_progress_is_not_concealed
    run_history('error')
  end

  def test_changed_lock_during_progress_is_not_rebound
    run_history('lock')
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def run_history(mode)
    Dir.mktmpdir('riddim-watch-history-') do |root|
      state = File.join(root, 'state')
      Dir.mkdir(state, 0o700)
      write_notification_worker(state, GEN)
      status_path = File.join(state, "worker.#{GEN}.status")
      File.write(status_path, "done [at=1]: retained report #{'x' * 120}\n" * 400, perm: 0o600)
      previous = ENV.fetch('RIDDIM_STATE_DIR', nil)
      begin
        ENV['RIDDIM_STATE_DIR'] = state
        Riddim::Notifications.scan(observe_activity: false).each { |entry| Riddim::Notifications.acknowledge(entry.id) }
      ensure
        ENV['RIDDIM_STATE_DIR'] = previous
      end
      File.write(File.join(state, 'slow-read'), '') if mode == 'slow'
      env = { 'RIDDIM_HISTORY_MODE' => mode, 'RIDDIM_STATE_DIR' => state, 'RIDDIM_ACTOR' => nil,
              'RIDDIM_STATUS_PATH' => status_path, 'RIDDIM_PHASE_TRACE' => File.join(root, 'phases'),
              'RIDDIM_EXTENSION' => File.expand_path('../.pi/extensions/riddim-notifications.ts', __dir__),
              'RUBYOPT' => "-r#{File.expand_path('support/notification_history_backend', __dir__)}" }
      out, err, status = Bundler.with_unbundled_env do
        script = %w[slow post-ready].include?(mode) ? 'notification_history.mts' : 'notification_history_failure.mts'
        Open3.capture3(env, 'node', File.expand_path("support/#{script}", __dir__))
      end

      phases = File.readlines(File.join(root, 'phases')).grep(/ phase-/)
      puts "#{mode} scan phases: #{phases.map(&:strip).join('; ')}"

      assert_predicate status, :success?, "#{out}\n#{err}"
      puts out
    end
  end
end
