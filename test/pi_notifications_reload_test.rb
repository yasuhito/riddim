# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'json'
require 'open3'
require 'pty'
require 'timeout'
require 'socket'
require 'tmpdir'
require 'fileutils'
require_relative '../scripts/pi_stall_server'
require_relative 'support/notification_worker_fixture'

# Actual interactive Pi /reload, not RPC new_session or a simulated lifecycle.
# All state, model traffic and child processes belong to this disposable lab.
# rubocop:disable-next Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Minitest/MultipleAssertions
class PiNotificationsReloadTest < Minitest::Test
  include NotificationWorkerFixture

  CLI = File.expand_path('../bin/riddim', __dir__)
  EXT = File.expand_path('../.pi/extensions/riddim-notifications.ts', __dir__)
  PROBE = File.expand_path('support/notification_reload_probe.ts', __dir__)
  GEN = 's1767200000.4242.7'

  def setup
    skip 'Pi executable unavailable on PATH' unless system('pi', '--version', out: File::NULL, err: File::NULL)

    @root = Dir.mktmpdir('riddim-pi-reload-')
    @state = File.join(@root, 'state')
    Dir.mkdir(@state)
    @trace = File.join(@root, 'trace.jsonl')
    @server = TCPServer.new('127.0.0.1', 0)
    PiStallLab::LabServer.config(@root, @server.addr[1])
    write_notification_worker(@state, GEN)
    @status = File.join(@state, "worker.#{GEN}.status")
    File.write(@status, '', perm: 0o600)
    @held = Queue.new
    @release = Queue.new
    @model = Thread.new do
      loop do
        socket = PiStallLab::LabServer.accept_http_request(@server)
        PiStallLab::LabServer.read_body(socket)
        if @hold_response
          @held << socket
          @release.pop
        end
        PiStallLab::LabServer.send_ok(socket)
        socket.close
      end
    end
    env = { 'PI_CODING_AGENT_DIR' => @root, 'PI_OFFLINE' => '1', 'PI_TELEMETRY' => '0',
            'RIDDIM_STATE_DIR' => @state, 'RIDDIM_ACTOR' => nil, 'RIDDIM_RELOAD_TRACE' => @trace,
            'TERM' => 'xterm-256color', 'PATH' => "#{ruby_shim}:#{ENV.fetch('PATH')}" }
    @output, @input, @pid = Bundler.with_unbundled_env do
      PTY.spawn(env, 'pi', '--no-tools', '--no-extensions', '--no-skills', '--no-prompt-templates',
                '--no-context-files', '-e', EXT, '-e', PROBE, '--session-dir', @root,
                '--model', 'stall-lab/test', '--thinking', 'off', '--tui-mode', 'regular', chdir: @root)
    end
    @waiter = Process.detach(@pid)
    @reader = Thread.new do
      File.open(File.join(@root, 'terminal.log'), 'w') do |log|
        loop do
          log.write(@output.readpartial(16_384))
          log.flush
        end
      end
    rescue Errno::EIO, IOError
      # PTY reports EIO when its child closes the terminal.
    end
    wait_until { rows.any? { |row| row['type'] == 'start' } }
  end

  def teardown
    stop_pi
    @reader&.join(2)
    @model&.kill
    @model&.join
    [@input, @output, @server].compact.each(&:close)
    preserve_evidence
  end

  def stop_pi
    return unless @pid && @waiter&.alive?

    Process.kill('TERM', @pid)
    raise "Test Pi #{@pid} did not shut down" unless @waiter.join(8)
  end

  def pending_ids
    cli('scan').map { |row| row.fetch('id') }
  end

  def preserve_evidence
    return unless @root

    evidence = ENV.fetch('RIDDIM_TEST_EVIDENCE_DIR', nil)
    FileUtils.cp_r(@root, evidence) if evidence && File.directory?(evidence)
    FileUtils.remove_entry(@root)
  end

  def ruby_shim
    dir = File.join(@root, 'bin')
    Dir.mkdir(dir)
    File.write(File.join(dir, 'ruby'), <<~SH)
      #!/bin/sh
      if [ "$1" = "#{CLI}" ] && [ "$2" = "watch-notifications" ]; then
        if [ -e "#{File.join(@root, 'deny')}" ]; then
          echo refused >> "#{File.join(@root, 'refusals')}"
          echo 'injected reload-lab refusal' >&2
          exit 1
        fi
        echo spawn >> "#{File.join(@root, 'spawns')}"
      fi
      exec "#{RbConfig.ruby}" "$@"
    SH
    File.chmod(0o700, File.join(dir, 'ruby'))
    dir
  end

  def rows
    return [] unless File.exist?(@trace)

    File.readlines(@trace).filter_map { |line| JSON.parse(line) if line.end_with?("\n") }
  end

  def wait_until
    Timeout.timeout(20) { sleep 0.02 until yield }
  end

  def cli(*)
    out, err, status = Bundler.with_unbundled_env do
      Open3.capture3({ 'RIDDIM_STATE_DIR' => @state }, CLI, 'notifications', *)
    end
    raise err unless status.success?

    JSON.parse(out)
  end

  def identity(path)
    stat = File.lstat(path)
    "#{stat.dev}:#{stat.ino}"
  end

  def children
    File.read("/proc/#{@pid}/task/#{@pid}/children").split.map(&:to_i)
  end

  def report(sequence)
    File.open(@status, 'a') { |file| file.puts "blocked [at=#{sequence}]: report #{sequence}" }
    wait_for_user("worker.#{GEN}.#{sequence}")
    wait_for_settled
  end

  def wait_for_user(text, boundary: 0)
    wait_until { rows.drop(boundary).any? { |row| row['type'] == 'user' && row.to_s.include?(text) } }
  end

  def wait_for_settled
    wait_until { rows.last&.fetch('type') == 'settled' }
  end

  def test_actual_reload_is_refused_while_streaming_without_replacing_the_watcher
    @hold_response = true
    @input.write("Keep streaming\r")
    Timeout.timeout(20) { @held.pop }
    before = children
    @input.write("/reload\r")
    wait_until do
      File.read(File.join(@root, 'terminal.log')).include?('Wait for the current response to finish before reloading.')
    end

    assert_equal before, children
    assert_equal(1, rows.count { |row| row['type'] == 'start' })
    refute(rows.any? { |row| row['type'] == 'shutdown' })
    @release << true
    wait_for_settled
  end

  def test_exhausted_recovery_then_actual_reload_preserves_identity_and_explicit_ack
    first_start = rows.find { |row| row['type'] == 'start' }

    refute_includes first_start['commands'].to_s, 'riddim-watch-arm'
    assert_equal 1, first_start['children'].size
    lock = File.join(@state, '.notification-watcher.lock')
    original = [identity(@state), identity(lock)]
    report(1)
    cli('scan')
    cli('ack', "worker.#{GEN}.1")
    report(2)
    File.write(File.join(@root, 'deny'), '')
    retired = children.fetch(0)
    Process.kill('TERM', retired)
    wait_for_user('automatic recovery exhausted')
    wait_for_settled

    assert_equal 3, File.readlines(File.join(@root, 'refusals')).size
    assert_empty children
    # Report data is durable even with no delivery process alive.
    File.open(@status, 'a') { |file| file.puts 'done [at=3]: written during outage' }

    assert_equal ["worker.#{GEN}.2", "worker.#{GEN}.3"], pending_ids
    assert_equal original, [identity(@state), identity(lock)]
    File.unlink(File.join(@root, 'deny'))
    boundary = rows.size
    @input.write("/reload\r")
    wait_until { rows.drop(boundary).any? { |row| row['type'] == 'start' && row['reason'] == 'reload' } }
    wait_for_user("worker.#{GEN}.3", boundary: boundary)
    wait_for_settled
    fresh = rows.drop(boundary)
    restarted = fresh.find { |row| row['type'] == 'start' }
    replay = fresh.select { |row| row['type'] == 'user' }.to_s

    assert_equal 'shutdown', fresh.first['type']
    assert_equal 'reload', fresh.first['reason']
    refute_equal first_start['runtime'], restarted['runtime']
    refute_includes restarted['commands'].to_s, 'riddim-watch-arm'
    assert_equal 1, restarted['children'].size
    assert_equal 1, children.size
    refute_includes children, retired
    assert_equal original, [identity(@state), identity(lock)]
    assert File.open(lock) { |file| !file.flock(File::LOCK_EX | File::LOCK_NB) }
    assert_includes replay, "worker.#{GEN}.2"
    assert_includes replay, "worker.#{GEN}.3"
    refute_includes replay, "worker.#{GEN}.1"
    assert_includes replay, 'Watcher successor is ready.'
    assert_equal ["worker.#{GEN}.2", "worker.#{GEN}.3"], pending_ids
  end
end
