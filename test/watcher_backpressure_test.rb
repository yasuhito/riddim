# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'tmpdir'
require 'timeout'
require 'open3'
require_relative '../lib/riddim/notifications'
require_relative 'support/notification_worker_fixture'

class WatcherBackpressureTest < Minitest::Test
  include NotificationWorkerFixture

  CLI = File.expand_path('../bin/riddim', __dir__)
  GEN = 's1767200000.4242.7'

  # Fill an actual pipe before launching our observer, then never drain it.
  # Slow per-record validation forces its first checkpoint inside the name
  # lock. A Worker report must still complete, not wait for Pi to read stdout.
  # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Minitest/MultipleAssertions
  def test_unread_observer_pipe_does_not_hold_worker_report_lock
    # Keep the report's fsync off a contended persistent filesystem: the
    # three-second assertion measures pipe/lock progress, not disk throughput.
    # Only private data lives here; all executables stay in the checkout.
    Dir.mktmpdir('riddim-backpressure-', '/dev/shm') do |state| # rubocop:disable Metrics/BlockLength
      File.chmod(0o700, state)
      write_notification_worker(state, GEN)
      File.write(File.join(state, "worker.#{GEN}.status"), "done [at=1]: retained\n" * 400, perm: 0o600)
      write_handled_notification_history(state, GEN, count: 400)
      reader, writer = IO.pipe
      loop { break if writer.write_nonblock('x' * 4096, exception: false) == :wait_writable }
      File.write(File.join(state, 'slow-read'), '')
      env = { 'RIDDIM_STATE_DIR' => state, 'RIDDIM_PHASE_TRACE' => File.join(state, 'phases'),
              'RUBYOPT' => "-r#{File.expand_path('support/notification_backpressure_backend', __dir__)}" }
      error = File.join(state, 'watch-error')
      exclusions = File.join(state, 'exclusions')
      File.write(exclusions, '[]')
      watcher = Bundler.with_unbundled_env do
        Process.spawn(env, RbConfig.ruby, CLI, 'watch-notifications', '--nonce', '0' * 32, '--exclude-stdin',
                      in: exclusions, out: writer, err: error)
      end
      writer.close
      begin
        Timeout.timeout(5) { sleep 0.01 until File.exist?(File.join(state, 'checkpoint-attempt')) }
      rescue Timeout::Error
        flunk "no scan checkpoint: #{File.read(error)}; trace exists: #{File.exist?(File.join(state, 'phases'))}"
      end
      File.unlink(File.join(state, 'slow-read')) # Finish remaining units quickly, without changing an in-flight write.
      input, output, errors, report = Bundler.with_unbundled_env do
        Open3.popen3({ 'RIDDIM_STATE_DIR' => state }, CLI, 'report', 'worker', '--generation', GEN,
                     'working [at=2]: report despite unread pipe')
      end
      input.close

      assert report.join(3), 'observer stdout backpressure retained the Worker name lock'
      assert_predicate report.value, :success?, errors.read
      assert Process.kill(0, watcher), 'observer should still be alive, blocked outside the Worker lock'
    ensure
      Process.kill('KILL', watcher) if watcher
      Process.wait(watcher) if watcher
      Process.kill('KILL', report.pid) if report&.alive?
      report&.join(2)
      [reader, writer, input, output, errors].each { |io| io&.close unless io&.closed? }
    end
  end
end
