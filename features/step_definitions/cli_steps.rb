# frozen_string_literal: true

Given('a fake Herdr executable') do
  directory = Dir.mktmpdir
  @temporary_directories << directory
  herdr = File.join(directory, 'herdr')
  File.write(herdr, <<~RUBY)
    #!/usr/bin/ruby
    puts ARGV.join(" ")
  RUBY
  File.chmod(0o755, herdr)
  @environment = { 'PATH' => "#{directory}:#{ENV.fetch('PATH')}" }
end

When('I run riddim with:') do |arguments|
  environment = @environment || {}
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

Then('standard error is empty') do
  assert_empty @stderr
end

Then('standard error is {string}') do |text|
  assert_equal "#{text}\n", @stderr
end
