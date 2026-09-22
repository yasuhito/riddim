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

When('I run riddim with:') do |arguments|
  # One resolved session per run: an ambient HERDR_SESSION is stripped so
  # Riddim targets Herdr's default session unless the scenario names one.
  environment = { 'HERDR_SESSION' => nil }.merge(@environment || {})
  Bundler.with_unbundled_env do
    @stdout, @stderr, @status = Open3.capture3(environment, RiddimWorld::RIDDIM, *Shellwords.split(arguments))
  end
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
    #{LOG_INVOCATION}
    #{SESSION_GUARD}
    #{body}
  RUBY
  File.chmod(0o755, herdr)
  @herdr_directory = directory
  @environment = (@environment || {}).merge('PATH' => "#{directory}:#{ENV.fetch('PATH')}")
end
