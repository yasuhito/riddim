# frozen_string_literal: true

Given('a fake Herdr executable') do
  install_fake_herdr(<<~RUBY)
    puts [*session_argv, *ARGV].join(' ')
  RUBY
end

Given('Herdr returns agent JSON:') do |json|
  install_fake_herdr(<<~RUBY)
    abort "unexpected arguments: \#{ARGV.join(' ')}" unless ARGV == %w[agent get pi]
    puts #{json.dump}
  RUBY
end

Given('Herdr fails with status {int} and error {string}') do |status, error|
  install_fake_herdr(<<~RUBY)
    abort "unexpected arguments: \#{ARGV.join(' ')}" unless ARGV == %w[agent get pi]
    warn #{error.dump}
    exit #{status}
  RUBY
end

Given('the Herdr session is {string}') do |session|
  @environment = (@environment || {}).merge('HERDR_SESSION' => session)
end

# Runs bin/riddim once against this scenario's child environment: one
# resolved session per run (an ambient HERDR_SESSION is stripped so Riddim
# targets Herdr's default session unless the scenario names one), plus the
# scenario's own environment values.
def run_riddim(*)
  environment = { 'HERDR_SESSION' => nil }.merge(@environment || {})
  Bundler.with_unbundled_env do
    Open3.capture3(environment, RiddimWorld::RIDDIM, *)
  end
end

When('I run riddim with:') do |arguments|
  @stdout, @stderr, @status = run_riddim(*Shellwords.split(arguments))
end

# Launches two same-name start processes at once, so the per-name lock, not
# scheduling, decides which one publishes its record.
When('I run two riddim starts of {string} at the same time') do |name|
  threads = Array.new(2) { Thread.new { run_riddim('start', name) } }
  @concurrent_starts = threads.map(&:value)
end

Then('Herdr receives {string}') do |invocation|
  assert_equal "#{invocation}\n", @stdout
end

Then('the command succeeds') do
  assert_predicate @status, :success?
end

Then('the command exits with status {int}') do |exit_status|
  assert_equal exit_status, @status.exitstatus
end

Then('standard output is empty') do
  assert_empty @stdout
end

Then('standard output includes {string}') do |text|
  assert_includes @stdout, text
end

Then('standard error includes {string}') do |text|
  assert_includes @stderr, text
end

Then('standard output is {string}') do |text|
  assert_equal "#{text}\n", @stdout
end

Then('standard error is empty') do
  assert_empty @stderr
end

Then('standard error is {string}') do |text|
  assert_equal "#{text}\n", @stderr
end

Then('Herdr is invoked with {string}') do |invocation|
  assert_equal [invocation], herdr_invocations
end

CLIENT_STATUS_FIXTURE = <<~'RUBY'
  if ARGV == %w[status --json]
    fixture = File.expand_path('client-status.json', __dir__)
    if File.file?(fixture)
      File.open(File.expand_path('invocations', __dir__), 'a') do |file|
        file.write([*session_argv, *ARGV].join(' ') + "\n")
      end
      print File.read(fixture)
    else
      puts '{"client":{"protocol":22,"version":"0.9.0"},"server":{"running":false}}'
    end
    exit 0
  end
RUBY

PROCESS_INFO_FIXTURE = <<~RUBY
  if ARGV[0, 2] == %w[pane process-info]
    require 'json'
    if File.exist?(File.expand_path('bad-process-info', __dir__))
      puts 'not JSON'
      exit 0
    end
    pane = ARGV[3]
    kind = File.exist?(File.expand_path('stale-pi', __dir__)) ? 'zsh' : 'pi'
    foreground = { pid: Process.ppid, name: kind, argv0: kind }
    result = { type: 'pane_process_info', process_info: {
      pane_id: pane, shell_pid: Process.ppid, foreground_processes: [foreground]
    } }
    puts JSON.generate(result: result)
    exit 0
  end
RUBY

# Installs a process-level Herdr test double while exercising the public CLI.
# Every invocation is logged beside the fake, and every invocation must be
# session-targeted: HERDR_SESSION set in the subprocess environment and an
# explicit --session argument naming that same session ahead of the
# subcommand.
def install_fake_herdr(body)
  directory = Dir.mktmpdir
  @temporary_directories << directory
  herdr = File.join(directory, 'herdr')
  File.write(herdr, <<~RUBY)
    #!/usr/bin/ruby
    #{SESSION_GUARD}
    #{CLIENT_STATUS_FIXTURE}
    #{LOG_INVOCATION.sub('ARGV.join', '[*session_argv, *ARGV].join')}
    #{PROCESS_INFO_FIXTURE}
    #{body}
  RUBY
  File.chmod(0o755, herdr)
  @herdr_directory = directory
  @environment = (@environment || {}).merge('PATH' => "#{directory}:#{ENV.fetch('PATH')}")
end
