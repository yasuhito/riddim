# frozen_string_literal: true

Given('the recorded prompt observes whether the lock for {string} is held') do |name|
  install_fake_herdr(<<~RUBY)
    lock_path = File.join(ENV.fetch('RIDDIM_STATE_DIR'), ".meta-#{name}.lock")
    File.open(lock_path, File::RDWR) do |lock|
      abort 'per-name lock was not held during prompt' if lock.flock(File::LOCK_EX | File::LOCK_NB)
    end
    puts 'prompt observed held lock'
  RUBY
end

Given('Herdr retains the send lock after the controller dies for {string}') do |name|
  install_fake_herdr(<<~RUBY)
    controller = Process.ppid
    Process.kill('KILL', controller)
    100.times do
      break if Process.ppid != controller
      sleep 0.01
    end
    abort 'controller did not exit' if Process.ppid == controller
    path = File.join(ENV.fetch('RIDDIM_STATE_DIR'), ".meta-#{name}.lock")
    held = File.open(path, File::RDWR) { |lock| !lock.flock(File::LOCK_EX | File::LOCK_NB) }
    abort 'Herdr lost ownership lock' unless held
    File.write(File.expand_path('inherited-send-lock', __dir__), 'yes')
  RUBY
end

Then('the Herdr send child retained the lock after controller death') do
  marker = File.join(@herdr_directory, 'inherited-send-lock')
  observed = 100.times.any? do
    found = File.exist?(marker)
    sleep 0.01 unless found
    found
  end
  assert observed
end

Given('the recorded prompt sends signal {string} to its controller') do |signal|
  install_fake_herdr(<<~RUBY)
    Process.kill(#{signal.dump}, Process.ppid)
    sleep 2
  RUBY
end

Given('the recorded prompt terminates from signal {string}') do |signal|
  install_fake_herdr(<<~RUBY)
    Process.kill(#{signal.dump}, Process.pid)
    sleep
  RUBY
end

Given('no Herdr executable is available') do
  directory = new_temporary_directory
  @herdr_directory = directory
  @environment = (@environment || {}).merge('PATH' => directory)
end

Given('the recorded prompt fails with status {int}, output {string}, and error {string}') do |status, output, error|
  install_fake_herdr(<<~RUBY)
    abort "unexpected arguments: \#{ARGV.join(' ')}" unless ARGV == ['agent', 'prompt', 'w9:p1', 'Fix the tests']
    puts #{output.dump}
    warn #{error.dump}
    exit #{status}
  RUBY
end

Then('the command is terminated by signal {string}') do |signal|
  assert_equal Signal.list.fetch(signal), @status.termsig
end
