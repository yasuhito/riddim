# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'json'
require 'open3'
require 'socket'
require 'timeout'
require 'tmpdir'
require 'fileutils'
require_relative '../scripts/pi_stall_server'
require_relative 'support/notification_worker_fixture'

# A real Pi process, isolated home and loopback-only model API. No fake Pi
# stdout: the assertion is Pi's own RPC user message and model HTTP request.
# rubocop:disable-next Metrics/ClassLength
class PiNotificationsE2ETest < Minitest::Test
  include NotificationWorkerFixture

  CLI = File.expand_path('../bin/riddim', __dir__)
  EXT = File.expand_path('../.pi/extensions/riddim-notifications.ts', __dir__)
  GEN = 's1767200000.4242.7'

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def setup
    skip 'Pi executable unavailable on PATH' unless ENV.fetch('PATH').split(File::PATH_SEPARATOR).any? do |dir|
      File.executable?(File.join(dir, 'pi')) && File.file?(File.join(dir, 'pi'))
    end

    @root = Dir.mktmpdir('riddim-pi-notifications-')
    @state = File.join(@root, 'state')
    FileUtils.mkdir_p(@state)
    @server = TCPServer.new('127.0.0.1', 0)
    PiStallLab::LabServer.config(@root, @server.addr[1])
    write_notification_worker(@state, GEN)
    @status_path = File.join(@state, "worker.#{GEN}.status")
    File.write(@status_path, '', mode: 'w', perm: 0o600)
    env = { 'PI_CODING_AGENT_DIR' => @root, 'PI_OFFLINE' => '1', 'PI_TELEMETRY' => '0',
            'RIDDIM_STATE_DIR' => @state, 'RIDDIM_ACTOR' => nil }
    env['PATH'] = "#{watcher_ruby_bin}:#{ENV.fetch('PATH')}"
    @input, @output, @error, @wait = Bundler.with_unbundled_env do
      Open3.popen3(env, 'pi', '--mode', 'rpc', '--no-tools', '--no-extensions', '--no-skills',
                   '--no-prompt-templates', '--no-context-files', '--extension', EXT, '--session-dir', @root,
                   '--model', 'stall-lab/test', '--thinking', 'off')
    end
  end

  # A local Ruby shim refuses the second watcher launch only. Pi and the
  # provider are real; no user credentials or remote API are involved.
  def watcher_ruby_bin
    dir = File.join(@root, 'bin')
    FileUtils.mkdir_p(dir)
    install_probe_herdr(dir)
    executable = File.join(dir, 'ruby')
    count = File.join(@root, 'watcher-spawns')
    deny = File.join(@root, 'deny-watcher-rearm')
    File.write(executable, <<~SH)
      #!/bin/sh
      if [ "$1" = "#{CLI}" ] && [ "$2" = "watch-notifications" ]; then
        export RUBYOPT="-r#{File.expand_path('support/notification_slow_backend', __dir__)} ${RUBYOPT:-}"
        if [ -e "#{count}" ] && [ -e "#{deny}" ]; then
          echo refused >> "#{File.join(@root, 'watcher-refusals')}"
          echo 'injected watcher rearm failure' >&2
          exit 1
        fi
        if [ -e "#{File.join(@root, 'replace-lock-rearm')}" ]; then
          mv "#{File.join(@state, '.notification-watcher.lock')}" "#{File.join(@state, '.old-lock')}"
          (umask 077; touch "#{File.join(@state, '.notification-watcher.lock')}")
        fi
        if [ -e "#{File.join(@state, 'idle')}" ]; then
          export RUBYOPT="-r#{File.expand_path('support/notification_stop_backend', __dir__)} ${RUBYOPT:-}"
        fi
        echo spawn >> "#{count}"
      fi
      exec "#{RbConfig.ruby}" "$@"
    SH
    File.chmod(0o700, executable)
    dir
  end

  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  # rubocop:disable-next Metrics/CyclomaticComplexity
  # rubocop:disable-next Metrics/MethodLength, Metrics/PerceivedComplexity
  def teardown
    begin
      Process.kill('CONT', @paused_watcher) if @paused_watcher
    rescue Errno::ESRCH
      # The watchdog already reaped the stopped watcher.
    end
    @input&.close
    if @wait&.alive?
      Process.kill('TERM', @wait.pid)
      @wait.join(5)
    end
    kill_probe_processes
    [@output, @error, @server].each { |io| io&.close }
    FileUtils.remove_entry(@root) if @root && File.exist?(@root)
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def install_probe_herdr(dir)
    original = ENV.fetch('PATH').split(File::PATH_SEPARATOR).map { |part| File.join(part, 'herdr') }
                  .find { |path| File.executable?(path) && File.file?(path) }
    original ||= File.join(dir, 'unavailable-herdr')
    path = File.join(dir, 'herdr')
    File.write(path, <<~RUBY)
      #!#{RbConfig.ruby}
      if ARGV.include?('riddim-test-probe')
        File.open(#{File.join(@state, 'probe-pids').dump}, 'a') { |f| f.puts(Process.pid) }
        sleep Float(File.read(#{File.join(@state, 'herdr-delay').dump}))
        puts '{}'
      else
        exec(#{original.dump}, *ARGV)
      end
    RUBY
    File.chmod(0o700, path)
  end

  def kill_probe_processes
    path = File.join(@state, 'probe-pids') if @state
    return unless path && File.exist?(path)

    File.readlines(path).each do |line|
      pid = Integer(line)
      command = File.binread("/proc/#{pid}/cmdline")
      Process.kill('KILL', pid) if command.include?(File.join(@root, 'bin/herdr'))
    rescue Errno::ESRCH, Errno::ENOENT
      # The bounded probe already retired this process.
    end
  end

  def wait_for_probe
    Timeout.timeout(10) do
      sleep 0.01 until File.exist?(File.join(@state, 'probe-pids'))
    end
  end

  def arm_watcher
    @input.puts JSON.generate(type: 'prompt', message: '/riddim-watch-arm', id: 'arm')
    until_event { |item| item['type'] == 'extension_ui_request' && item['message'] == 'Riddim watcher ready' }
  end

  def event(timeout: 20)
    Timeout.timeout(timeout) do
      line = @output.gets
      raise "Pi exited: #{@error.read}" unless line

      JSON.parse(line)
    end
  end

  def until_event(timeout: 20)
    loop do
      item = event(timeout: timeout)
      return item if yield(item)
    end
  end

  def request
    Timeout.timeout(20) { PiStallLab::LabServer.receive_request(@server) }
  end

  def report(text)
    File.open(@status_path, 'a') { |file| file.write("#{text}\n") }
  end

  def cli(*)
    Bundler.with_unbundled_env do
      Open3.capture3({ 'RIDDIM_STATE_DIR' => @state }, CLI, 'notifications', *)
    end
  end

  def notification(timeout: 20)
    until_event(timeout: timeout) do |item|
      item['type'] == 'message_start' && item.dig('message', 'role') == 'user' &&
        item.dig('message', 'content').to_s.include?('Riddim Supervisor notification')
    end
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Minitest/MultipleAssertions
  def test_cumulative_slow_herdr_probes_do_not_starve_heartbeat_or_recovery_budget
    arm_watcher
    4.times do |index|
      name = "worker#{index}"
      write_notification_worker(@state, GEN, name: name)
      File.write(File.join(@state, "#{name}.#{GEN}.status"), '', perm: 0o600)
    end
    File.write(File.join(@state, 'herdr-delay'), '0.4')
    wait_for_probe
    sleep 6
    @input.puts JSON.generate(type: 'prompt', message: '/riddim-watch-arm', id: 'probe')
    verdict = until_event { |item| item['type'] == 'extension_ui_request' && item['method'] == 'notify' }

    assert_equal 'Riddim watcher ready', verdict['message']
    assert_equal 1, File.readlines(File.join(@root, 'watcher-spawns')).size
    assert_path_exists File.join(@state, '.notifications', ".idle-worker0-#{GEN}")
    assert_path_exists File.join(@state, '.notifications', ".idle-worker1-#{GEN}")
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Minitest/MultipleAssertions
  def test_hung_herdr_does_not_block_worker_report_progress
    arm_watcher
    File.write(File.join(@state, 'herdr-delay'), '60')
    wait_for_probe
    diagnostic = File.join(@root, 'report-error')
    pid = Bundler.with_unbundled_env do
      Process.spawn({ 'RIDDIM_STATE_DIR' => @state }, CLI, 'report', 'worker', '--generation', GEN,
                    'blocked [at=1]: report during hung observation', out: File::NULL, err: diagnostic)
    end
    reporter = Process.detach(pid)

    assert reporter.join(1), 'a hung observation held the Worker report lock for over one second'
    assert_predicate reporter.value, :success?, File.read(diagnostic)
    assert_includes notification.to_s, "worker.#{GEN}.1"
    socket = request
    PiStallLab::LabServer.send_ok(socket)
    socket.close
  ensure
    Process.kill('TERM', pid) if reporter&.alive?
    reporter&.join(2)
  end

  # Real Pi accepts the attention follow-up for the native alive+idle+no-report
  # fixture, without treating that observation as a worker completion claim.
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Minitest/MultipleAssertions
  def test_live_idle_attention_is_consumed_by_real_pi_without_a_worker_report
    @input.puts JSON.generate(type: 'prompt', message: '/riddim-watch-arm', id: 'arm')
    until_event { |item| item['type'] == 'extension_ui_request' && item['message'] == 'Riddim watcher ready' }
    File.write(File.join(@state, 'idle'), '')
    watcher = File.read("/proc/#{@wait.pid}/task/#{@wait.pid}/children").split.first.to_i
    Process.kill('TERM', watcher) # Automatic replacement loads the native-state fixture.
    message = notification(timeout: 45)

    assert_includes message.to_s, "worker.#{GEN}.0"
    assert_includes message.to_s, 'not completion'
    assert_empty File.read(@status_path)
    out, err, status = cli('scan')

    assert_predicate status, :success?, err
    assert_equal(['unreported-idle'], JSON.parse(out).map { |row| row.fetch('event') })
    socket = request
    PiStallLab::LabServer.send_ok(socket)
    socket.close
  end

  # A launch holds the name lock through registration. It must not starve
  # the supervisor observer's heartbeat while Pi waits for that launch.
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Minitest/MultipleAssertions
  def test_busy_worker_lock_does_not_kill_supervisor_watcher
    @input.puts JSON.generate(type: 'prompt', message: '/riddim-watch-arm', id: 'arm')
    until_event { |item| item['type'] == 'extension_ui_request' && item['message'] == 'Riddim watcher ready' }
    File.open(File.join(@state, '.meta-worker.lock'), File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      report('blocked [at=1]: report waits behind launch')
      sleep 6
      @input.puts JSON.generate(type: 'prompt', message: '/riddim-watch-arm', id: 'probe')
      verdict = until_event { |item| item['type'] == 'extension_ui_request' && item['method'] == 'notify' }

      assert_equal 'Riddim watcher ready', verdict['message']
      assert_equal 'info', verdict['notifyType']
    end
    assert_includes notification.to_s, "worker.#{GEN}.1"
    socket = request
    PiStallLab::LabServer.send_ok(socket)
    socket.close
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Minitest/MultipleAssertions
  # rubocop:disable-next Metrics/CyclomaticComplexity
  def test_stopped_watcher_is_automatically_replaced_before_claiming_ready
    @input.puts JSON.generate(type: 'prompt', message: '/riddim-watch-arm', id: 'probe')
    verdict = until_event do |item|
      item['type'] == 'extension_ui_request' && item['method'] == 'notify' &&
        item['message'] == 'Riddim watcher ready'
    end

    assert_equal 'info', verdict['notifyType']
    @paused_watcher = Integer(File.read("/proc/#{@wait.pid}/task/#{@wait.pid}/children").split.first)
    Process.kill('STOP', @paused_watcher)
    replacement = nil
    Timeout.timeout(12) do
      loop do
        replacement = File.read("/proc/#{@wait.pid}/task/#{@wait.pid}/children").split.first&.to_i
        break if replacement && replacement != @paused_watcher

        sleep 0.05
      end
    end
    @input.puts JSON.generate(type: 'prompt', message: '/riddim-watch-arm', id: 'recovered')
    alarm = until_event do |item|
      item['type'] == 'extension_ui_request' && item['method'] == 'notify'
    end

    assert_equal 'Riddim watcher ready', alarm['message']
    assert_equal 'info', alarm['notifyType']
    refute_equal @paused_watcher, replacement
    report('blocked [at=1]: waiting after verified recovery')
    out, err, status = cli('scan')

    assert_predicate status, :success?, err
    assert_equal(["worker.#{GEN}.1"], JSON.parse(out).map { |row| row.fetch('id') })
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Minitest/MultipleAssertions
  def test_unexpected_close_retries_are_bounded_and_alarm_only_once
    @input.puts JSON.generate(type: 'prompt', message: '/riddim-watch-arm', id: 'arm')
    until_event { |item| item['type'] == 'extension_ui_request' && item['message'] == 'Riddim watcher ready' }
    File.write(File.join(@root, 'deny-watcher-rearm'), '')
    watcher = File.read("/proc/#{@wait.pid}/task/#{@wait.pid}/children").split.first.to_i
    Process.kill('TERM', watcher)
    alarm = until_event do |item|
      item['type'] == 'extension_ui_request' && item['method'] == 'notify'
    end

    assert_includes alarm['message'], 'automatic recovery exhausted'
    assert_equal 'error', alarm['notifyType']
    # Every refusal is counted separately from a successful initial spawn.
    assert_equal 3, File.readlines(File.join(@root, 'watcher-refusals')).size
    sleep 1

    assert_equal 3, File.readlines(File.join(@root, 'watcher-refusals')).size
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Minitest/MultipleAssertions
  def test_lock_replaced_during_retry_is_not_accepted_as_recovery
    @input.puts JSON.generate(type: 'prompt', message: '/riddim-watch-arm', id: 'arm')
    until_event { |item| item['type'] == 'extension_ui_request' && item['message'] == 'Riddim watcher ready' }
    File.write(File.join(@root, 'replace-lock-rearm'), '')
    watcher = File.read("/proc/#{@wait.pid}/task/#{@wait.pid}/children").split.first.to_i
    Process.kill('TERM', watcher)
    alarm = until_event do |item|
      item['type'] == 'extension_ui_request' && item['method'] == 'notify'
    end

    assert_includes alarm['message'], 'changed ownership after readiness'
    sleep 1

    assert_equal 2, File.readlines(File.join(@root, 'watcher-spawns')).size
  end

  # rubocop:disable-next Metrics/AbcSize, Minitest/MultipleAssertions
  def test_changed_lock_is_not_rebound_by_automatic_recovery
    @input.puts JSON.generate(type: 'prompt', message: '/riddim-watch-arm', id: 'arm')
    until_event { |item| item['type'] == 'extension_ui_request' && item['message'] == 'Riddim watcher ready' }
    path = File.join(@state, '.notification-watcher.lock')
    File.rename(path, "#{path}.old")
    File.write(path, '', perm: 0o600)
    alarm = until_event do |item|
      item['type'] == 'extension_ui_request' && item['method'] == 'notify'
    end

    assert_includes alarm['message'], 'ownership ambiguous'
    assert_equal 1, File.readlines(File.join(@root, 'watcher-spawns')).size
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Minitest/MultipleAssertions
  def test_failed_rearm_reports_failure_and_retains_report
    Timeout.timeout(5) { sleep 0.01 until File.exist?(File.join(@root, 'watcher-spawns')) }
    File.write(File.join(@root, 'deny-watcher-rearm'), '')
    report('blocked [at=1]: private body')
    alarm = until_event do |item|
      item['type'] == 'message_start' && item.dig('message', 'role') == 'user' &&
        item.dig('message', 'content').to_s.include?('Riddim watcher FAILED')
    end

    assert_includes alarm.to_s, 'repair with /riddim-watch-arm'
    first = request
    PiStallLab::LabServer.send_ok(first)
    first.close
    message = notification

    assert_includes message.to_s, "worker.#{GEN}.1"
    assert_includes message.to_s, 'Watcher FAILED'
    out, err, status = cli('scan')

    assert_predicate status, :success?, err
    assert_equal(["worker.#{GEN}.1"], JSON.parse(out).map { |row| row.fetch('id') })
    socket = request
    PiStallLab::LabServer.send_ok(socket)
    socket.close
  end

  # Replacement during a busy turn must re-present any unhandled ID,
  # whether Pi accepted the first follow-up yet or not.
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Minitest/MultipleAssertions
  def test_replacement_replays_unhandled_report_during_busy_turn
    @input.puts JSON.generate(type: 'prompt', message: 'Keep streaming')
    busy = request
    report('blocked [at=1]: private body')
    state = nil
    Timeout.timeout(10) do
      loop do
        @input.puts JSON.generate(type: 'get_state', id: 'busy')
        state = until_event { |item| item['type'] == 'response' && item['id'] == 'busy' }
        break if state.dig('data', 'pendingMessageCount').positive?

        sleep 0.05
      end
    end

    assert state.dig('data', 'isStreaming')
    assert_equal 1, state.dig('data', 'pendingMessageCount')
    @input.puts JSON.generate(type: 'new_session', id: 'replacement')
    until_event { |item| item['type'] == 'response' && item['id'] == 'replacement' }
    replay = notification

    assert_includes replay.to_s, "worker.#{GEN}.1"
    busy.close
    socket = request
    PiStallLab::LabServer.send_ok(socket)
    socket.close
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Minitest/MultipleAssertions
  def test_idle_and_busy_follow_ups_are_consumed_but_not_acknowledged
    report('blocked [at=1]: private arbitrary body')
    first = notification

    assert_includes first.to_s, "worker.#{GEN}.1"
    refute_includes first.to_s, 'private arbitrary body'
    socket = request
    PiStallLab::LabServer.send_ok(socket)
    socket.close
    until_event { |item| item['type'] == 'agent_settled' }

    @input.puts JSON.generate(type: 'prompt', message: 'First request')
    busy = request
    report('done [at=2]: second private body')
    # While the first request is still streaming, a follow-up is accepted
    # into Pi's queue, not delivered as an interrupt.
    sleep 0.7
    @input.puts JSON.generate(type: 'get_state', id: 'busy')
    state = until_event { |item| item['type'] == 'response' && item['id'] == 'busy' }

    assert state.dig('data', 'isStreaming')
    PiStallLab::LabServer.send_ok(busy)
    busy.close
    second = notification

    assert_includes second.to_s, "worker.#{GEN}.2"
    refute_includes second.to_s, 'second private body'
    followup = request
    PiStallLab::LabServer.send_ok(followup)
    followup.close
    until_event { |item| item['type'] == 'agent_settled' }

    out, err, status = cli('scan')

    assert_predicate status, :success?, err
    assert_equal(["worker.#{GEN}.1", "worker.#{GEN}.2"], JSON.parse(out).map { |row| row.fetch('id') })
    cli('ack', "worker.#{GEN}.1")
    out, = cli

    assert_equal(["worker.#{GEN}.2"], JSON.parse(out).map { |row| row.fetch('id') })

    @input.puts JSON.generate(type: 'new_session', id: 'replacement')
    replacement = nil
    replay = nil
    until replacement && replay
      item = event
      replacement = item if item['type'] == 'response' && item['id'] == 'replacement'
      replay = item if item['type'] == 'message_start' && item.dig('message', 'role') == 'user' &&
                       item.dig('message', 'content').to_s.include?('Riddim Supervisor notification')
    end

    assert replacement['success']
    # Unhandled rows are replayed in the new session, independent of API acceptance.
    assert_includes replay.to_s, "worker.#{GEN}.2"
    socket = request
    PiStallLab::LabServer.send_ok(socket)
    socket.close
    until_event { |item| item['type'] == 'agent_settled' }
  end
end
