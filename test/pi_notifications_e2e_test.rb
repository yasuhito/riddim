# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'json'
require 'open3'
require 'socket'
require 'timeout'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/riddim/ownership'
require_relative '../scripts/pi_stall_server'

# A real Pi process, isolated home and loopback-only model API. No fake Pi
# stdout: the assertion is Pi's own RPC user message and model HTTP request.
# rubocop:disable-next Metrics/ClassLength
class PiNotificationsE2ETest < Minitest::Test
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
    fields = { 'harness' => 'pi', 'model' => 'stall-lab/test', 'effort' => 'off', 'spawn_gen' => GEN,
               'backend' => 'herdr', 'herdr_workspace_id' => 'w9', 'herdr_tab_id' => 'w9:t1',
               'window' => 'test:w9:p1', 'endpoint_task_id' => 'worker', 'herdr_session' => 'test',
               'herdr_pane_id' => 'w9:p1', 'task_mode' => 'local-only', 'status_protocol' => 'locked-v1' }
    File.write(File.join(@state, 'worker.meta'), Riddim::Ownership.serialize(fields), mode: 'w', perm: 0o600)
    @status_path = File.join(@state, "worker.#{GEN}.status")
    File.write(@status_path, '', mode: 'w', perm: 0o600)
    env = { 'PI_CODING_AGENT_DIR' => @root, 'PI_OFFLINE' => '1', 'PI_TELEMETRY' => '0',
            'RIDDIM_STATE_DIR' => @state }
    @input, @output, @error, @wait = Bundler.with_unbundled_env do
      Open3.popen3(env, 'pi', '--mode', 'rpc', '--no-tools', '--no-extensions', '--no-skills',
                   '--no-prompt-templates', '--no-context-files', '--extension', EXT, '--session-dir', @root,
                   '--model', 'stall-lab/test', '--thinking', 'off')
    end
  end

  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  # rubocop:disable-next Metrics/CyclomaticComplexity
  def teardown
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
