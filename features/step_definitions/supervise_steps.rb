# frozen_string_literal: true

require 'json'
require_relative '../../lib/riddim/runtime_paths'

Given('Herdr reports a running supported server') do
  install_supervisor_herdr_status(
    client: { protocol: 22, version: '0.9.0' },
    server: { running: true, version: '0.9.0' }
  )
end

Given('Herdr cannot be reached') do
  install_supervisor_herdr_status(
    { client: { protocol: 22, version: '0.9.0' }, server: { running: true, version: '0.9.0' } },
    fail: true
  )
end

Given('Herdr reports a stopped server') do
  install_supervisor_herdr_status(
    client: { protocol: 22, version: '0.9.0' },
    server: { running: false }
  )
end

Given('a fake supervisor Pi executable') do
  install_fake_pi
end

Given('no explicit Riddim state directory') do
  inherited_home = Riddim::RuntimePaths.read_for_source
  @default_state_dir = if inherited_home
                         inherited_home.fetch('state_dir')
                       else
                         File.expand_path('../state', File.dirname(RiddimWorld::RIDDIM))
                       end
  @default_state_dir_preexisting = File.exist?(@default_state_dir) || File.symlink?(@default_state_dir)
  @temporary_directories << @default_state_dir unless @default_state_dir_preexisting
  @environment = @environment.merge('RIDDIM_STATE_DIR' => nil)
end

Given('the selected Riddim state directory is a symlink') do
  directory = new_temporary_directory
  target = File.join(directory, 'real-state')
  Dir.mkdir(target)
  @state_dir_symlink = File.join(directory, 'state-link')
  File.symlink(target, @state_dir_symlink)
  @environment = @environment.merge('RIDDIM_STATE_DIR' => @state_dir_symlink)
end

Then('Pi receives the supervisor launch arguments and selected state directory') do
  assert_equal expected_supervisor_arguments, pi_capture.fetch('argv')
  assert_equal scenario_state_dir, pi_capture.fetch('state_dir')
  assert_equal 0o700, pi_capture.fetch('state_dir_mode')
end

Then('Pi receives supervisor retirement instructions:') do |table|
  prompt = pi_capture.fetch('supervisor_prompt').split.join(' ')
  table.hashes.each { |row| assert_includes prompt, row.fetch('instruction') }
end

Then('Pi receives the supervisor launch arguments and default state directory') do
  assert_equal expected_supervisor_arguments, pi_capture.fetch('argv')
  assert_equal @default_state_dir, pi_capture.fetch('state_dir')
  assert_equal 0o700, pi_capture.fetch('state_dir_mode')
end

Then('Herdr is queried only for the running status of session {string}') do |session|
  assert_equal ["--session #{session} status --json"], herdr_invocations,
               "exit=#{@status.exitstatus} stderr=#{@stderr.inspect} stdout=#{@stdout.inspect}"
end

Then("the supervisor Pi resolves riddim to this checkout's CLI") do
  assert_equal File.expand_path(RiddimWorld::RIDDIM), pi_capture.fetch('riddim')
end

Then('the supervisor command reports its usage and invokes neither Herdr nor Pi') do
  assert_equal 2, @status.exitstatus
  assert_equal "Usage: riddim supervise\n", @stderr
  assert_empty herdr_invocations
  refute pi_started?
end

Then('the supervisor reports the missing profile before invoking Herdr or Pi') do
  assert_equal 1, @status.exitstatus
  assert_equal "riddim: missing profile file: agent-profile\n", @stderr
  assert_empty herdr_invocations
  refute pi_started?
end

Then('the supervisor reports that Herdr is unreachable and does not launch Pi') do
  assert_equal 1, @status.exitstatus
  assert_equal "riddim: Herdr is not reachable in session default: status failed\n", @stderr
  assert_equal ['--session default status --json'], herdr_invocations
  refute pi_started?
end

Then('the supervisor reports that Herdr is not ready and does not launch Pi') do
  assert_equal 1, @status.exitstatus
  expected_error = <<~ERROR
    riddim: Herdr is not ready in session default: Herdr server is not running in session default
  ERROR
  assert_equal expected_error, @stderr
  assert_equal ['--session default status --json'], herdr_invocations
  refute pi_started?
end

Then('the supervisor refuses a symlinked state directory without launching Pi') do
  assert_equal 1, @status.exitstatus
  expected_error = <<~ERROR
    riddim: could not prepare Riddim state directory #{@state_dir_symlink}: the state directory is not a real directory: #{@state_dir_symlink}
  ERROR
  assert_equal expected_error, @stderr
  assert_equal ['--session default status --json'], herdr_invocations
  refute pi_started?
end

def install_supervisor_herdr_status(document = nil, fail: false, **fields)
  document ||= fields
  install_fake_herdr("abort 'unexpected Herdr invocation'")
  File.write(File.join(@herdr_directory, 'client-status.json'), JSON.generate(document))
  File.write(File.join(@herdr_directory, 'status-fails'), '') if fail
end

def install_fake_pi
  directory = Dir.mktmpdir
  @temporary_directories << directory
  @pi_capture = File.join(directory, 'capture.json')
  @pi_started = File.join(directory, 'started')
  pi = File.join(directory, 'pi')
  File.write(pi, fake_pi_script)
  File.chmod(0o755, pi)
  configure_fake_pi_environment(directory)
end

def configure_fake_pi_environment(directory)
  @environment = (@environment || {}).merge(
    'PATH' => "#{directory}:#{@environment.fetch('PATH', ENV.fetch('PATH'))}",
    'PI_CAPTURE' => @pi_capture,
    'PI_STARTED' => @pi_started
  )
end

def fake_pi_script
  <<~RUBY
    #!/usr/bin/ruby
    require 'json'
    state_dir = ENV.fetch('RIDDIM_STATE_DIR')
    riddim = ENV.fetch('PATH').split(':').map { |dir| File.join(dir, 'riddim') }
                .find { |path| File.file?(path) && File.executable?(path) }
    prompt_path = ARGV.fetch(ARGV.index('--append-system-prompt') + 1)
    File.write(ENV.fetch('PI_CAPTURE'), JSON.generate(argv: ARGV, state_dir: state_dir, riddim: riddim,
                                                       supervisor_prompt: File.read(prompt_path),
                                                       state_dir_mode: File.stat(state_dir).mode & 0o777))
    File.write(ENV.fetch('PI_STARTED'), 'started')
  RUBY
end

def pi_capture
  JSON.parse(File.read(@pi_capture))
end

def pi_started?
  File.file?(@pi_started)
end

def expected_supervisor_arguments
  root = File.expand_path('..', File.dirname(RiddimWorld::RIDDIM))
  [
    '--model', 'openrouter/z-ai/glm-5.3-flash', '--thinking', 'max',
    '-e', File.join(root, '.pi/extensions/riddim-notifications.ts'),
    '--append-system-prompt', File.join(root, 'docs/supervisor.md')
  ]
end
