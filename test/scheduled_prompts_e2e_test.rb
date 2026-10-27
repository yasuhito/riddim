# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'json'
require 'open3'
require 'socket'
require 'timeout'
require 'tmpdir'
require 'fileutils'
require 'time'
require_relative '../scripts/pi_stall_server'

# Actual Pi and CLI, with disposable state and a loopback-only model.
# rubocop:disable-next Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Minitest/MultipleAssertions, Metrics/CyclomaticComplexity
class ScheduledPromptsE2ETest < Minitest::Test
  CLI = File.expand_path('../bin/riddim', __dir__)
  EXT = File.expand_path('../.pi/extensions/riddim-notifications.ts', __dir__)

  def setup
    @root = Dir.mktmpdir('riddim-scheduled-pi-')
    @state = File.join(@root, 'state')
    Dir.mkdir(@state, 0o700)
    @server = TCPServer.new('127.0.0.1', 0)
    PiStallLab::LabServer.config(@root, @server.addr[1])
    @events = []
    start_pi
    @session = state.fetch('sessionId')
    wait_for_watcher
  end

  def start_pi(session_file = nil)
    env = { 'PI_CODING_AGENT_DIR' => @root, 'PI_OFFLINE' => '1', 'PI_TELEMETRY' => '0',
            'RIDDIM_STATE_DIR' => @state, 'RIDDIM_ACTOR' => nil }
    args = ['pi', '--mode', 'rpc', '--no-tools', '--no-extensions', '--no-skills',
            '--no-prompt-templates', '--no-context-files', '-e', EXT, '--session-dir', File.join(@root, 'pi-sessions'),
            '--model', 'stall-lab/test', '--thinking', 'off']
    args += ['--session', session_file] if session_file
    @input, @output, @error, @wait = Bundler.with_unbundled_env { Open3.popen3(env, *args, chdir: @root) }
  end

  def stop_pi
    @input&.close
    if @wait&.alive?
      Process.kill('TERM', @wait.pid)
      raise 'isolated Pi did not stop' unless @wait.join(8)
    end
    @output&.close
    return unless @error && !@error.closed?

    File.open(File.join(@root, 'pi-stderr.log'), 'a') { |file| file.write(@error.read) }
    @error.close
  end

  def teardown
    stop_pi
    @server&.close
    return unless @root

    File.write(File.join(@root, 'events.json'), JSON.pretty_generate(@events))
    evidence = ENV.fetch('RIDDIM_TEST_EVIDENCE_DIR', nil)
    FileUtils.cp_r(@root, evidence) if evidence && File.directory?(evidence)
    FileUtils.remove_entry(@root)
  end

  def event
    Timeout.timeout(20) do
      line = @output.gets
      raise "Pi exited: #{@error.read}" unless line

      JSON.parse(line).tap { |item| @events << item }
    end
  end

  def until_event
    loop do
      item = event
      return item if yield(item)
    end
  end

  def state
    @input.puts JSON.generate(type: 'get_state', id: 'state')
    until_event { |item| item['type'] == 'response' && item['id'] == 'state' }.fetch('data')
  end

  def wait_for_watcher
    Timeout.timeout(5) do
      loop do
        lock = File.join(@state, '.notification-watcher.lock')
        break if File.exist?(lock) && File.open(lock) { |file| !file.flock(File::LOCK_EX | File::LOCK_NB) }

        sleep 0.01
      end
    end
  end

  def cli(*)
    out, err, status = Bundler.with_unbundled_env do
      Open3.capture3({ 'RIDDIM_STATE_DIR' => @state, 'RIDDIM_ACTOR' => nil }, CLI, 'schedule', *)
    end

    assert_predicate status, :success?, "#{out}\n#{err}"
    JSON.parse(out)
  end

  def create(at: Time.now - 1, every: nil, session: @session)
    path = File.join(@root, 'prompt.txt')
    File.write(path, 'Check the explicitly authorized local task. $(not-a-shell-command)')
    args = ['create', '--session', session, '--at', at.iso8601, '--prompt-file', path]
    args += ['--every', every] if every
    cli(*args)
  end

  def delivered
    message = until_event do |item|
      item['type'] == 'message_start' && item.dig('message', 'role') == 'user' &&
        item.dig('message', 'content').to_s.include?('Riddim scheduled prompt')
    end
    socket = Timeout.timeout(20) { PiStallLab::LabServer.receive_request(@server) }
    PiStallLab::LabServer.send_ok(socket)
    socket.close
    until_event { |item| item['type'] == 'agent_settled' }
    message.to_s
  end

  def test_recurring_overdue_coalesces_and_same_session_restart_replays_until_explicit_ack
    schedule = create(at: Time.now - 7200, every: '30m')
    text = delivered
    before = cli('list').fetch(0)
    id = before.fetch('occurrence').fetch('id')

    assert_includes text, id
    assert_operator before.fetch('next_at'), :>, Time.now.to_i
    file = state.fetch('sessionFile')

    assert_path_exists file, 'actual Pi must persist the session before a resume test'
    stop_pi

    assert_path_exists file
    start_pi(file)

    assert_equal @session, state.fetch('sessionId')
    assert_includes delivered, id
    after = cli('list').fetch(0)

    assert_equal before.fetch('occurrence'), after.fetch('occurrence')
    cli('ack', id, '--session', @session)

    assert_empty cli('scan', '--session', @session)
    cli('cancel', schedule.fetch('id'))

    assert cli('list').fetch(0).fetch('cancelled')
  end

  def test_different_session_cannot_receive_or_ack_and_original_can_resume
    schedule = create
    delivered
    id = cli('list').fetch(0).fetch('occurrence').fetch('id')
    original_file = state.fetch('sessionFile')

    assert_path_exists original_file
    @input.puts JSON.generate(type: 'new_session', id: 'new')
    until_event { |item| item['type'] == 'response' && item['id'] == 'new' }
    different = state.fetch('sessionId')

    refute_equal @session, different
    assert_empty cli('scan', '--session', different)
    _out, err, status = Bundler.with_unbundled_env do
      Open3.capture3({ 'RIDDIM_STATE_DIR' => @state, 'RIDDIM_ACTOR' => nil },
                     CLI, 'schedule', 'ack', id, '--session', different)
    end

    refute_predicate status, :success?
    assert_includes err, 'different Pi session'
    boundary = @events.size
    # A prompt/response roundtrip establishes that the replacement observer has
    # started without requiring a timed negative assertion or external model.
    @input.puts JSON.generate(type: 'prompt', message: 'Unrelated session roundtrip')
    socket = Timeout.timeout(20) { PiStallLab::LabServer.receive_request(@server) }
    PiStallLab::LabServer.send_ok(socket)
    socket.close
    until_event { |item| item['type'] == 'agent_settled' }

    refute_includes @events.drop(boundary).to_s, 'Riddim scheduled prompt'
    assert_equal schedule.fetch('id'), cli('list').fetch(0).fetch('id')
    stop_pi
    start_pi(original_file)
    state

    assert_includes delivered, id
  end

  def test_observer_recovery_delivers_later_schedule_without_replaying_accepted_occurrence
    create
    first = delivered
    original_children = File.read("/proc/#{@wait.pid}/task/#{@wait.pid}/children").split.map(&:to_i)

    assert_equal 1, original_children.size
    Process.kill('TERM', original_children.fetch(0))
    second_schedule = create
    second = delivered

    assert_includes second, "scheduled.#{second_schedule.fetch('id')}.1"
    refute_equal first, second
    assert_equal 2, cli('list').size
  end

  def test_cancellation_remains_visible_without_dispatch_to_a_replacement_session
    schedule = create(at: Time.now + 60)
    cli('cancel', schedule.fetch('id'))

    assert_nil cli('list').fetch(0).fetch('occurrence')
    assert_empty cli('scan', '--session', @session)
  end

  def observer_failure
    until_event do |item|
      item['type'] == 'message_start' && item.dig('message', 'role') == 'user' &&
        item.dig('message', 'content').to_s.include?('Riddim watcher FAILED')
    end
    socket = Timeout.timeout(20) { PiStallLab::LabServer.receive_request(@server) }
    PiStallLab::LabServer.send_ok(socket)
    socket.close
    until_event { |item| item['type'] == 'agent_settled' }
  end

  def test_corrupt_schedule_store_fails_observer_without_dispatch_or_silent_repair
    create(at: Time.now + 60)
    store = File.join(@state, '.scheduled-prompts.json')
    File.write(store, '{corrupt')
    observer_failure

    assert_equal '{corrupt', File.read(store)
    refute_includes @events.to_s, 'Riddim scheduled prompt'
  end

  def test_replaced_source_lock_refuses_schedule_delivery_and_rebinding
    create(at: Time.now + 60)
    lock = File.join(@state, '.notification-watcher.lock')
    File.rename(lock, "#{lock}.original")
    File.write(lock, '', perm: 0o600)
    observer_failure
    _out, error, status = Bundler.with_unbundled_env do
      Open3.capture3({ 'RIDDIM_STATE_DIR' => @state, 'RIDDIM_ACTOR' => nil }, CLI, 'schedule', 'list')
    end

    refute_predicate status, :success?
    assert_includes error, 'ownership changed'
    refute_includes @events.to_s, 'Riddim scheduled prompt'
  end

  def test_busy_follow_up_coalesces_and_cancellation_does_not_claim_retraction
    @input.puts JSON.generate(type: 'prompt', message: 'An already running authorized task')
    busy = Timeout.timeout(20) { PiStallLab::LabServer.receive_request(@server) }
    schedule = create(at: Time.now - 30, every: '1s')
    row = nil
    Timeout.timeout(5) do
      loop do
        row = cli('list').fetch(0)
        break if row.dig('occurrence', 'offered')

        sleep 0.02
      end
    end
    first = row.fetch('occurrence').fetch('id')
    boundary = row.fetch('next_at') + 2
    Timeout.timeout(5) do
      loop do
        row = cli('list').fetch(0)
        break if row.fetch('next_at') >= boundary

        sleep 0.02
      end
    end

    assert_equal first, row.fetch('occurrence').fetch('id')
    assert state.fetch('isStreaming')
    user_messages = @events.select { |item| item['type'] == 'message_start' && item.dig('message', 'role') == 'user' }

    refute_includes user_messages.to_s, 'Riddim scheduled prompt'
    queues = @events.select { |item| item['type'] == 'queue_update' }

    assert_includes queues.last.fetch('followUp').to_s, first
    assert_empty queues.last.fetch('steering')
    cli('cancel', schedule.fetch('id'))
    PiStallLab::LabServer.send_ok(busy)
    busy.close

    assert_includes delivered, first
    assert_equal 'cancelled', cli('list').fetch(0).fetch('occurrence').fetch('status')
    cli('ack', first, '--session', @session)

    assert_empty cli('scan', '--session', @session)
  ensure
    busy&.close unless busy&.closed?
  end

  def test_one_shot_reaches_only_explicit_session_and_requires_handling_ack
    schedule = create(at: Time.now + 2)
    text = delivered

    assert_includes text, '$(not-a-shell-command)'
    assert_includes text, 'not Worker reports'
    row = cli('list').fetch(0)

    assert_equal schedule.fetch('id'), row.fetch('id')
    occurrence = row.fetch('occurrence').fetch('id')

    assert_includes text, occurrence
    assert_equal 'pending', row.fetch('occurrence').fetch('status')
    cli('ack', occurrence, '--session', @session)

    assert_equal 'handled', cli('list').fetch(0).fetch('occurrence').fetch('status')
    assert_empty cli('scan', '--session', @session)
  end
end
