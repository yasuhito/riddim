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

# Native project discovery in a fresh clone, never an explicitly loaded -e.
# rubocop:disable-next Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Minitest/MultipleAssertions
class PiNativeStartupTest < Minitest::Test
  SOURCE = File.expand_path('..', __dir__)

  def setup
    skip 'Pi executable unavailable on PATH' unless system('pi', '--version', out: File::NULL, err: File::NULL)

    @root = Dir.mktmpdir('riddim-native-startup-')
    @checkout = File.join(@root, 'checkout')
    run!('git', 'clone', '--quiet', '--no-hardlinks', SOURCE, @checkout)
    @home = File.join(@root, 'home')
    Dir.mkdir(@home)
    @server = TCPServer.new('127.0.0.1', 0)
    PiStallLab::LabServer.config(@home, @server.addr[1])
    @config = File.join(@root, 'config')
    Dir.mkdir(@config)
    File.write(File.join(@config, 'agent-profile'), "pi stall-lab/test low\n")
    @processes = []
    @streams = {}
    @events = []
    @shim = install_supervise_dependencies
  end

  def teardown
    @processes&.reverse_each { |process| close_process(process) }
    @server&.close
    FileUtils.remove_entry(@root) if @root
  end

  def close_process(process)
    input, output, error, waiter = process
    input.close unless input.closed?
    unless waiter.join(8)
      Process.kill('TERM', waiter.pid)
      raise "Test-owned Pi #{waiter.pid} did not stop after TERM" unless waiter.join(5)
    end
    @streams.fetch(waiter.pid).fetch(:readers).each(&:join)
    output.close
    error.close
  end

  def run!(*args)
    out, err, status = Open3.capture3(*args)
    raise "#{args.inspect}: #{out}#{err}" unless status.success?

    out
  end

  def pi_environment(state: nil, actor: nil)
    { 'PI_CODING_AGENT_DIR' => @home, 'PI_OFFLINE' => '1', 'PI_TELEMETRY' => '0',
      'RIDDIM_CONFIG_DIR' => @config, 'RIDDIM_STATE_DIR' => state, 'RIDDIM_ACTOR' => actor,
      'RIDDIM_SUPERVISE' => nil, 'PATH' => @shim }
  end

  def start_pi(cwd: @checkout, state: nil, actor: nil, trust: true, extra_args: [])
    env = pi_environment(state: state, actor: actor)
    process = Bundler.with_unbundled_env do
      Open3.popen3(env, @real_pi, trust ? '--approve' : '--no-approve', '--mode', 'rpc', '--no-tools', '--no-skills',
                   '--no-prompt-templates', '--no-context-files', '--model', 'stall-lab/test',
                   '--thinking', 'off', *extra_args, chdir: cwd)
    end
    record_process(process)
  end

  def record_process(process)
    @processes << process
    _, output, error, waiter = process
    queue = Queue.new
    # Pi emits the full system prompt before HTTP dispatch. Consume both pipes
    # continuously, including while the test waits on HTTP rather than RPC.
    stdout = Thread.new do
      output.each_line { |line| queue << line }
    ensure
      queue << nil
    end
    stderr = Thread.new { error.read }
    @streams[waiter.pid] = { queue: queue, readers: [stdout, stderr] }
    process
  end

  def response(process, type, **payload)
    process.first.puts JSON.generate(type: type, id: type, **payload)
    queue = @streams.fetch(process.last.pid).fetch(:queue)
    Timeout.timeout(20) do
      loop do
        row = JSON.parse(queue.pop || raise('Pi exited before its RPC response'))
        @events << row
        return row if row['type'] == 'response' && row['id'] == type
      end
    end
  end

  def wait_for_ready(process)
    Timeout.timeout(15) do
      loop do
        result = response(process, 'bash', command: 'riddim notifications scan')
        return result if result.dig('data', 'exitCode')&.zero? &&
                         watcher_locked?(@state)

        sleep 0.05
      end
    end
  end

  def watcher_locked?(state)
    path = File.join(state, '.notification-watcher.lock')
    return false unless File.exist?(path)

    File.open(path) { |lock| !lock.flock(File::LOCK_EX | File::LOCK_NB) }
  end

  def test_declining_project_trust_does_not_start_supervision
    process = start_pi(trust: false)
    commands = response(process, 'get_commands')

    refute_includes commands.to_s, 'riddim-watch-arm'
    refute_path_exists File.join(@checkout, 'state')
  end

  def test_explicit_home_is_preserved_without_creating_default_state
    @state = File.join(@root, 'selected-state')
    process = start_pi(state: @state, actor: '')
    wait_for_ready(process)
    path_before = response(process, 'bash', command: 'printf %s "$PATH"').dig('data', 'output')
    response(process, 'new_session')
    wait_for_ready(process)
    path_after = response(process, 'bash', command: 'printf %s "$PATH"').dig('data', 'output')

    refute_path_exists File.join(@checkout, 'state')
    assert watcher_locked?(@state)
    assert_equal path_before, path_after
  end

  def test_all_nonempty_actors_exclude_native_supervision
    %w[branch crew supervisor unknown].push(' ').each do |actor|
      state = File.join(@root, "actor-#{actor.strip}")
      process = start_pi(state: state, actor: actor)
      commands = response(process, 'get_commands')

      refute_includes commands.to_s, 'riddim-watch-arm'
      refute_path_exists state
    end
    refute_path_exists File.join(@checkout, 'state')
  end

  def test_unmarked_linked_worktree_cannot_become_supervisor_even_with_selected_home
    linked = File.join(@root, '.riddim-worktrees', 'riddim-local', 'worker')
    run!('git', '-C', @checkout, 'worktree', 'add', '--quiet', '-b', 'worker', linked)
    @state = File.join(@root, 'selected-state')
    process = start_pi(cwd: linked, state: @state)
    response(process, 'get_state')

    refute_path_exists @state
    refute_path_exists File.join(linked, 'state')
    commands = response(process, 'get_commands')

    refute_includes commands.to_s, 'riddim-watch-arm'
    refute_path_exists @state
  end

  def central_target_worktree
    target = File.join(@root, 'target')
    run!('git', 'init', '--quiet', target)
    run!('git', '-C', target, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
         'commit', '--allow-empty', '-qm', 'base')
    linked = File.join(@root, '.riddim-worktrees', 'target-local', 'worker')
    run!('git', '-C', target, 'worktree', 'add', '--quiet', '-b', 'worker', linked)
    linked
  end

  def test_unmarked_foreign_central_worktree_does_not_discover_supervision
    @state = File.join(@root, 'selected-state')
    process = start_pi(cwd: central_target_worktree, state: @state)
    commands = response(process, 'get_commands')

    refute_includes commands.to_s, 'riddim-watch-arm'
    refute_path_exists @state
    refute_path_exists File.join(@checkout, 'state')
  end

  def test_linked_runtime_explicit_supervise_from_central_worktree_keeps_selected_home
    linked_runtime = File.join(@root, '.riddim-worktrees', 'riddim-local', 'runtime')
    run!('git', '-C', @checkout, 'worktree', 'add', '--quiet', '-b', 'runtime', linked_runtime)
    @state = File.join(@root, 'selected-state')
    cwd = central_target_worktree
    process = Bundler.with_unbundled_env do
      Open3.popen3(pi_environment(state: @state), File.join(linked_runtime, 'bin/riddim'), 'supervise', chdir: cwd)
    end
    record_process(process)
    wait_for_ready(process)
    response(process, 'prompt', message: 'Describe your role')
    body = model_request

    assert watcher_locked?(@state)
    assert_equal 1, body.to_s.scan('You coordinate Riddim').size
    refute_path_exists File.join(cwd, 'state')
    refute_path_exists File.join(linked_runtime, 'state')
    refute_path_exists File.join(@checkout, 'state')
  end

  def test_competing_session_refuses_without_taking_over_after_owner_exits
    @state = File.join(@checkout, 'state')
    owner = start_pi
    wait_for_ready(owner)
    contender = start_pi
    response(contender, 'get_state')
    body = model_request

    refute_includes body.to_s, 'You coordinate Riddim'
    assert_includes body.to_s, 'Do not supervise or start workers'
    refute_includes @events.to_s, 'Riddim watcher ready'
    response(contender, 'get_state')

    assert_includes @events.to_s, 'Riddim watcher FAILED'
    assert watcher_locked?(@state)
    owner.first.close

    assert owner.last.join(8), 'owner did not shut down'
    sleep 0.5

    refute watcher_locked?(@state), 'contender took over the released watcher lock'
  end

  def test_missing_herdr_is_refused_before_state_or_watcher_initialization
    File.unlink(File.join(@shim, 'herdr'))
    process = start_pi
    response(process, 'get_state')

    assert_includes @events.to_s, 'Herdr is not reachable in session'
    refute_path_exists File.join(@checkout, 'state')
    process.first.puts JSON.generate(type: 'prompt', message: 'Describe your role')
    body = model_request

    refute_includes body.to_s, 'You coordinate Riddim'
    assert_includes body.to_s, 'Do not supervise or start workers'
  end

  def test_stopped_herdr_is_refused_before_state_or_watcher_initialization
    File.write(@herdr_status, 'stopped')
    process = start_pi
    response(process, 'get_state')

    assert_includes @events.to_s, 'Herdr server is not running'
    refute_path_exists File.join(@checkout, 'state')
  end

  def model_request
    socket = Timeout.timeout(20) { PiStallLab::LabServer.accept_http_request(@server) }
    JSON.parse(PiStallLab::LabServer.read_body(socket))
  ensure
    if socket
      PiStallLab::LabServer.send_ok(socket)
      socket.close
    end
  end

  def test_symlinked_selected_state_is_refused
    real = File.join(@root, 'real-state')
    Dir.mkdir(real)
    selected = File.join(@root, 'selected-state')
    File.symlink(real, selected)
    process = start_pi(state: selected)
    response(process, 'get_state')

    assert_includes @events.to_s, 'native startup FAILED'
    refute_path_exists File.join(real, '.notification-watcher.lock')
    commands = response(process, 'get_commands')

    refute_includes commands.to_s, 'riddim-watch-arm'
    assert_includes @events.to_s, 'use /reload or restart Pi'
    refute_includes @events.to_s, 'Riddim watcher ready'
    File.unlink(selected)
    process.first.close

    assert process.last.join(8), 'failed bootstrap process did not shut down'
    @state = selected
    wait_for_ready(start_pi(state: selected))

    assert watcher_locked?(selected), 'restart did not retry bootstrap after the path was repaired'
  end

  def test_legacy_supervise_without_marker_does_not_duplicate_contract
    @state = File.join(@root, 'selected-state')
    args = ['-e', File.join(@checkout, '.pi/extensions/riddim-notifications.ts'),
            '--append-system-prompt', File.join(@checkout, 'docs/supervisor.md')]
    process = start_pi(state: @state, extra_args: args)
    wait_for_ready(process)
    process.first.puts JSON.generate(type: 'prompt', message: 'Describe your role')
    body = model_request

    assert_equal 1, body.to_s.scan('You coordinate Riddim').size
  end

  def test_existing_supervise_uses_one_watcher_with_native_discovery_enabled
    @state = File.join(@root, 'selected-state')
    alias_root = File.join(@root, 'alias')
    File.symlink(@checkout, alias_root)
    env = pi_environment(state: @state)
    process = Bundler.with_unbundled_env do
      Open3.popen3(env, File.join(alias_root, 'bin/riddim'), 'supervise', chdir: alias_root)
    end
    record_process(process)
    wait_for_ready(process)
    children = File.read("/proc/#{process.last.pid}/task/#{process.last.pid}/children").split

    assert_equal 1, children.size
    assert watcher_locked?(@state)
    refute_path_exists File.join(@checkout, 'state')
    process.first.puts JSON.generate(type: 'prompt', message: 'Describe your role')
    body = model_request

    system_prompt = body.fetch('messages').find { |message| message.fetch('role') == 'system' }.fetch('content')

    assert_equal [1, true],
                 [body.to_s.scan('You coordinate Riddim').size,
                  system_prompt.include?(File.read(File.join(SOURCE, 'docs/supervisor.md')))]
  end

  def test_existing_supervise_does_not_hide_missing_isolated_profile
    File.unlink(File.join(@config, 'agent-profile'))
    @state = File.join(@root, 'selected-state')
    _out, error, status = Bundler.with_unbundled_env do
      Open3.capture3(pi_environment(state: @state), File.join(@checkout, 'bin/riddim'), 'supervise', chdir: @checkout)
    end

    assert_equal 1, status.exitstatus
    assert_includes error, 'missing profile file: agent-profile'
    refute_path_exists @state
  end

  def install_supervise_dependencies
    shim = File.join(@root, 'bin')
    Dir.mkdir(shim)
    @real_pi = run!('which', 'pi').strip
    %w[ruby git bash sh node].each do |command|
      File.symlink(run!('which', command).strip, File.join(shim, command))
    end
    File.write(File.join(shim, 'pi'), <<~SH)
      #!/bin/sh
      exec "#{@real_pi}" "$@" --approve --mode rpc --no-tools --no-skills --no-prompt-templates --no-context-files --model stall-lab/test --thinking off
    SH
    @herdr_status = File.join(@root, 'herdr-status')
    File.write(@herdr_status, 'running')
    File.write(File.join(shim, 'herdr'), <<~RUBY)
      #!#{RbConfig.ruby}
      running = File.read(#{@herdr_status.dump}).strip == 'running'
      puts %({"client":{"protocol":14,"version":"0.8.0"},"server":{"running":\#{running},"version":"0.8.0"}})
    RUBY
    %w[pi herdr].each { |name| File.chmod(0o700, File.join(shim, name)) }
    shim
  end

  def test_corrupt_scheduled_state_does_not_suppress_native_supervisor_contract_or_readiness
    @state = File.join(@checkout, 'state')
    Dir.mkdir(@state, 0o700)
    File.write(File.join(@state, '.scheduled-prompts.lock'), '', perm: 0o600)
    File.write(File.join(@state, '.scheduled-prompts.json'), '{corrupt', perm: 0o600)
    process = start_pi
    wait_for_ready(process)
    body = model_request # The bounded schedule diagnostic initiates this request.

    assert watcher_locked?(@state)
    assert_includes body.to_s, 'You coordinate Riddim'
    refute_includes body.to_s, 'Do not supervise or start workers'
    assert_includes @events.to_s, 'Riddim scheduled prompts FAILED'
    refute_includes @events.to_s, 'Riddim watcher FAILED'
  end

  def test_fresh_clone_initializes_default_home_and_injects_supervisor_contract
    @state = File.join(@checkout, 'state')
    process = start_pi
    result = wait_for_ready(process)

    assert_equal '[]', result.dig('data', 'output').strip
    assert_equal 0o700, File.stat(@state).mode & 0o777
    process.first.puts JSON.generate(type: 'prompt', message: 'Describe your role')
    body = model_request

    system_prompt = body.fetch('messages').find { |message| message.fetch('role') == 'system' }.fetch('content')

    assert_includes system_prompt, File.read(File.join(SOURCE, 'docs/supervisor.md'))
  end
end
