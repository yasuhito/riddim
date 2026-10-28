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
require_relative 'support/notification_worker_fixture'

# Actual Pi and CLI, with disposable state and a loopback-only model.
# rubocop:disable-next Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Minitest/MultipleAssertions, Metrics/CyclomaticComplexity
class ScheduledPromptsE2ETest < Minitest::Test
  include NotificationWorkerFixture

  CLI = File.expand_path('../bin/riddim', __dir__)
  EXT = File.expand_path('../.pi/extensions/riddim-notifications.ts', __dir__)

  def setup
    skip 'Pi executable unavailable on PATH' unless ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
      File.executable?(File.join(dir, 'pi')) && File.file?(File.join(dir, 'pi'))
    end

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
            'RIDDIM_STATE_DIR' => @state, 'RIDDIM_ACTOR' => nil, 'PATH' => "#{fault_shim}:#{ENV.fetch('PATH')}" }
    args = ['pi', '--mode', 'rpc', '--no-tools', '--no-extensions', '--no-skills',
            '--no-prompt-templates', '--no-context-files', '-e', EXT, '--session-dir', File.join(@root, 'pi-sessions'),
            '--model', 'stall-lab/test', '--thinking', 'off']
    args += ['--session', session_file] if session_file
    @input, @output, @error, @wait = Bundler.with_unbundled_env { Open3.popen3(env, *args, chdir: @root) }
  end

  def fault_shim
    dir = File.join(@root, 'bin')
    FileUtils.mkdir_p(dir)
    path = File.join(dir, 'ruby')
    File.write(path, <<~SH)
      #!/bin/sh
      if [ "$1" = "#{CLI}" ]; then
        if [ "$2" = "watch-notifications" ]; then
          if [ -e "#{@root}/deny-successor" ]; then
            echo refused >> "#{@root}/successor-refusals"
            echo 'injected successor refusal' >&2
            exit 1
          fi
          echo spawn >> "#{@root}/watcher-spawns"
        elif [ "$2" = "schedule" ] && [ "$3" = "offer" ] && [ -e "#{@root}/deny-offer" ]; then
          echo refused >> "#{@root}/offer-refusals"
          echo 'injected scheduled offer refusal' >&2
          exit 1
        fi
      fi
      exec "#{RbConfig.ruby}" "$@"
    SH
    File.chmod(0o700, path)
    dir
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

  def stop_initial_creation
    if @paused_creation
      Process.kill('KILL', @paused_creation.pid) if @paused_creation.alive?
      @paused_creation.join(2)
    end
    [@create_input, @create_output, @create_error].compact.each { |io| io.close unless io.closed? }
  end

  def teardown
    stop_initial_creation
    stop_pi
    @model_thread&.kill
    @model_thread&.join
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

  def respond_automatically
    @model_thread = Thread.new do
      loop do
        socket = PiStallLab::LabServer.receive_request(@server)
        PiStallLab::LabServer.send_ok(socket)
        socket.close
      end
    end
  end

  def worker_report(sequence = 1)
    generation = 's1767200000.4242.7'
    write_notification_worker(@state, generation)
    path = File.join(@state, "worker.#{generation}.status")
    File.write(path, '', perm: 0o600) unless File.exist?(path)
    out, err, result = Bundler.with_unbundled_env do
      Open3.capture3({ 'RIDDIM_STATE_DIR' => @state }, CLI, 'report', 'worker', '--generation', generation,
                     "blocked [at=#{sequence}]: ordinary Worker report #{sequence}")
    end

    assert_predicate result, :success?, "#{out}\n#{err}"
    "worker.#{generation}.#{sequence}"
  end

  def worker_delivered(id)
    message = until_event do |item|
      item['type'] == 'message_start' && item.dig('message', 'role') == 'user' &&
        item.dig('message', 'content').to_s.include?("Pending IDs: #{id}")
    end
    until_event { |item| item['type'] == 'agent_settled' }
    message.to_s
  end

  def test_corrupt_schedule_store_withholds_prompts_but_keeps_worker_reports_and_observer_alive
    create(at: Time.now + 60)
    store = File.join(@state, '.scheduled-prompts.json')
    original = File.read(store)
    before = File.readlines(File.join(@root, 'watcher-spawns')).size
    File.write(store, '{corrupt')
    respond_automatically
    id = worker_report
    text = worker_delivered(id)

    assert_includes text, id
    assert_equal '{corrupt', File.read(store)
    assert_equal before + 1, File.readlines(File.join(@root, 'watcher-spawns')).size
    refute_includes @events.to_s, 'Riddim watcher FAILED'
    refute_includes @events.to_s, '$(not-a-shell-command)'
    assert_includes @events.to_s, 'Riddim scheduled prompts FAILED'
    assert_equal(1, @events.count do |item|
      item['type'] == 'extension_ui_request' &&
          item['message'].to_s.include?('Riddim scheduled prompts FAILED')
    end)
    File.write(store, original)
    cli('cancel', cli('list').fetch(0).fetch('id'))
  end

  def test_missing_established_schedule_store_does_not_block_worker_reports
    create(at: Time.now + 60)
    File.unlink(File.join(@state, '.scheduled-prompts.json'))
    respond_automatically
    id = worker_report

    assert_includes worker_delivered(id), id
    refute_includes @events.to_s, 'Riddim watcher FAILED'
    assert_includes @events.to_s, 'Riddim scheduled prompts FAILED'
  end

  def with_paused_observer
    pid = File.read("/proc/#{@wait.pid}/task/#{@wait.pid}/children").split.map(&:to_i).fetch(0)
    Process.kill('STOP', pid)
    yield
  ensure
    Process.kill('CONT', pid) if pid
  end

  def mixed_batch(fault)
    # Pause only the exact owned observer, briefly, so one real scan sees both
    # the Worker report and scheduled occurrence. This is not a timeout race.
    with_paused_observer do
      schedule = create
      id = worker_report
      File.write(File.join(@root, fault), '')
      [schedule, id]
    end
  end

  def test_failed_successor_does_not_discard_worker_text_in_a_mixed_batch
    respond_automatically
    schedule, id = mixed_batch('deny-successor')
    text = worker_delivered(id)

    assert_includes text, 'successor readiness/liveness unverified'
    assert_includes @events.to_s, 'Riddim scheduled prompts FAILED'
    refute_includes @events.to_s, '$(not-a-shell-command)'
    row = cli('list').find { |entry| entry.fetch('id') == schedule.fetch('id') }

    refute row.fetch('occurrence').fetch('offered')
    assert_equal 'pending', row.fetch('occurrence').fetch('status')
    cli('cancel', schedule.fetch('id'))

    assert_empty cli('scan', '--session', @session)
    assert_equal 'cancelled', cli('list').fetch(0).fetch('occurrence').fetch('status')
  end

  def test_failed_offer_preserves_worker_delivery_and_pending_schedule_replays_after_same_session_restart
    respond_automatically
    schedule, id = mixed_batch('deny-offer')

    assert_includes worker_delivered(id), id
    assert_includes @events.to_s, 'Riddim scheduled prompts FAILED'
    refute_includes @events.to_s, '$(not-a-shell-command)'
    row = cli('list').find { |entry| entry.fetch('id') == schedule.fetch('id') }

    refute row.fetch('occurrence').fetch('offered')
    assert_equal 'pending', row.fetch('occurrence').fetch('status')
    second = worker_report(2)

    assert_includes worker_delivered(second), second
    assert_equal 1, File.readlines(File.join(@root, 'offer-refusals')).size
    _out, _err, refused_ack = Bundler.with_unbundled_env do
      Open3.capture3({ 'RIDDIM_STATE_DIR' => @state, 'RIDDIM_ACTOR' => nil },
                     CLI, 'schedule', 'ack', row.fetch('occurrence').fetch('id'), '--session', @session)
    end

    refute_predicate refused_ack, :success?
    file = state.fetch('sessionFile')
    stop_pi
    @model_thread.kill
    @model_thread.join
    @model_thread = nil
    File.unlink(File.join(@root, 'deny-offer'))
    # Handle the ordinary report so the restart only replays scheduled work.
    [id, second].each do |report_id|
      out, err, result = Bundler.with_unbundled_env do
        Open3.capture3({ 'RIDDIM_STATE_DIR' => @state }, CLI, 'notifications', 'ack', report_id)
      end

      assert_predicate result, :success?, "#{out}\n#{err}"
    end
    start_pi(file)

    assert_equal @session, state.fetch('sessionId')
    assert_includes delivered, "scheduled.#{schedule.fetch('id')}.1"
    cli('ack', "scheduled.#{schedule.fetch('id')}.1", '--session', @session)

    assert_empty cli('scan', '--session', @session)
  end

  def paused_initial_create
    path = File.join(@root, 'initial-prompt.txt')
    File.write(path, 'Explicitly authorized initialization recovery')
    env = { 'RIDDIM_STATE_DIR' => @state, 'RIDDIM_ACTOR' => nil,
            'RUBYOPT' => "-r#{File.expand_path('support/schedule_initialization_pause', __dir__)}",
            'RIDDIM_INIT_SIGNAL' => File.join(@root, 'init-signal'),
            'RIDDIM_INIT_RELEASE' => File.join(@root, 'init-release') }
    @create_input, @create_output, @create_error, @paused_creation = Bundler.with_unbundled_env do
      Open3.popen3(env, CLI, 'schedule', 'create', '--session', @session, '--every', '30m', '--prompt-file', path)
    end
    Timeout.timeout(5) { sleep 0.01 until File.exist?(env.fetch('RIDDIM_INIT_SIGNAL')) }
  end

  def test_interrupted_first_lock_creation_recovers_through_real_cli_without_lock_replacement
    paused_initial_create
    lock = File.join(@state, '.scheduled-prompts.lock')
    original_inode = File.stat(lock).ino
    Process.kill('KILL', @paused_creation.pid)
    @paused_creation.join(2)
    schedule = create

    assert_equal original_inode, File.stat(lock).ino
    assert_includes delivered, "scheduled.#{schedule.fetch('id')}.1"
    refute_includes @events.to_s, 'Riddim watcher FAILED'
  end

  def test_first_create_contender_can_initialize_while_original_opener_is_paused_before_flock
    paused_initial_create
    original_inode = File.stat(File.join(@state, '.scheduled-prompts.lock')).ino
    contender = create(at: Time.now + 60)
    File.write(File.join(@root, 'init-release'), '')

    assert @paused_creation.join(5), 'paused CLI failed to finish after release'
    assert_predicate @paused_creation.value, :success?, @create_error.read
    original = JSON.parse(@create_output.read)
    rows = cli('list')

    assert_equal [original.fetch('id'), contender.fetch('id')].sort, rows.map { |row| row.fetch('id') }.sort
    assert_equal original_inode, File.stat(File.join(@state, '.scheduled-prompts.lock')).ino
  end

  def initialization_disk_failure(stage)
    path = File.join(@root, 'initial-prompt.txt')
    File.write(path, 'Explicitly authorized initialization after disk recovery')
    env = { 'RIDDIM_STATE_DIR' => @state, 'RIDDIM_ACTOR' => nil, 'RIDDIM_INIT_FAULT' => stage,
            'RUBYOPT' => "-r#{File.expand_path('support/schedule_initialization_pause', __dir__)}" }
    # Ensure the faulted writer, not the scanner, reaches this initialization
    # boundary first. Resume the original observer before testing recovery.
    _out, error, result = with_paused_observer do
      Bundler.with_unbundled_env do
        Open3.capture3(env, CLI, 'schedule', 'create', '--session', @session, '--every', '30m', '--prompt-file', path)
      end
    end

    refute_predicate result, :success?
    assert_includes error, 'No space left on device'
    lock = File.join(@state, '.scheduled-prompts.lock')
    before = File.stat(lock).ino
    schedule = create

    assert_equal before, File.stat(lock).ino
    assert_equal([schedule.fetch('id')], cli('list').map { |row| row.fetch('id') })
    assert_includes delivered, "scheduled.#{schedule.fetch('id')}.1"
    refute_includes @events.to_s, 'Riddim watcher FAILED'
  end

  def test_disk_failure_after_first_open_does_not_permanently_poison_initialization
    initialization_disk_failure('open')
  end

  def test_disk_failure_after_initial_empty_document_can_recover_without_losing_work
    initialization_disk_failure('ready')
  end

  def test_disk_failure_after_durable_ready_marker_keeps_empty_store_safe_for_next_creation
    initialization_disk_failure('committed')
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
