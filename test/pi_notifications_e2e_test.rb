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
    @root = Dir.mktmpdir('riddim-pi-notifications-')
    @state = File.join(@root, 'state')
    FileUtils.mkdir_p(@state)
    @server = TCPServer.new('127.0.0.1', 0)
    PiStallLab::LabServer.config(@root, @server.addr[1])
    write_notification_worker(@state, GEN)
    @status_path = File.join(@state, "worker.#{GEN}.status")
    File.write(@status_path, '', mode: 'w', perm: 0o600)
    env = { 'PI_CODING_AGENT_DIR' => @root, 'PI_OFFLINE' => '1', 'PI_TELEMETRY' => '0',
            'RIDDIM_STATE_DIR' => @state }
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
    executable = File.join(dir, 'ruby')
    count = File.join(@root, 'watcher-spawns')
    deny = File.join(@root, 'deny-watcher-rearm')
    File.write(executable, <<~SH)
      #!/bin/sh
      if [ "$1" = "#{CLI}" ] && [ "$2" = "watch-notifications" ]; then
        if [ -e "#{count}" ] && [ -e "#{deny}" ]; then
          echo 'injected watcher rearm failure' >&2
          exit 1
        fi
        touch "#{count}"
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
    [@output, @error, @server].each { |io| io&.close }
    FileUtils.remove_entry(@root) if @root && File.exist?(@root)
  end

  def event
    Timeout.timeout(20) do
      line = @output.gets
      raise "Pi exited: #{@error.read}" unless line

      JSON.parse(line)
    end
  end

  def until_event
    loop do
      item = event
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

  def notification
    until_event do |item|
      item['type'] == 'message_start' && item.dig('message', 'role') == 'user' &&
        item.dig('message', 'content').to_s.include?('Riddim Supervisor notification')
    end
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Minitest/MultipleAssertions
  def test_stopped_watcher_is_reported_failed_not_healthy
    @input.puts JSON.generate(type: 'prompt', message: '/riddim-watch-arm', id: 'probe')
    verdict = until_event do |item|
      item['type'] == 'extension_ui_request' && item['method'] == 'notify' &&
        item['message'] == 'Riddim watcher ready'
    end

    assert_equal 'info', verdict['notifyType']
    @paused_watcher = Integer(File.read("/proc/#{@wait.pid}/task/#{@wait.pid}/children").split.first)
    Process.kill('STOP', @paused_watcher)
    alarm = until_event do |item|
      item['type'] == 'extension_ui_request' && item['method'] == 'notify' &&
        item['message'].to_s.include?('heartbeat stale')
    end

    assert_equal 'error', alarm['notifyType']
    report('blocked [at=1]: waiting during watcher failure')
    out, err, status = cli('scan')

    assert_predicate status, :success?, err
    assert_equal(["worker.#{GEN}.1"], JSON.parse(out).map { |row| row.fetch('id') })
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
