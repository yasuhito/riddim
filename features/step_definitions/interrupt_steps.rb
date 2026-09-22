# frozen_string_literal: true

require 'json'

# Builds one canned `herdr agent get` response for a Pi-like agent.
def pi_agent_response(kind: 'pi', pane_id: 'w9:p1', status: 'working')
  agent = { agent: kind, agent_status: status }
  agent[:pane_id] = pane_id unless pane_id.nil?
  JSON.generate(id: 'cli:agent:get', result: { type: 'agent_info', agent: agent })
end

# Accepts an interrupt of the exact recorded pane and keeps registering Pi.
Given('Herdr registers pane {string} as Pi and accepts its interrupt key') do |pane|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get'] then puts #{pi_agent_response(pane_id: pane).dump}
    when ['pane', 'send-keys'] then nil
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr registers pane {string} as {string}') do |pane, kind|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get'] then puts #{pi_agent_response(kind: kind, pane_id: pane).dump}
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr registers Pi at pane {string} without a pane id') do |_pane|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get'] then puts #{pi_agent_response(pane_id: nil).dump}
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr registration at pane {string} names pane {string}') do |_pane, other|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get'] then puts #{pi_agent_response(pane_id: other).dump}
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr writes captured output then terminates from signal {string} while reading the recorded pane') do |signal|
  install_fake_herdr(<<~RUBY)
    abort "unexpected arguments: \#{ARGV.join(' ')}" unless ARGV == %w[agent get w9:p1]
    $stdout.write("partial read\n")
    $stderr.write("herdr interrupted\n")
    $stdout.flush
    $stderr.flush
    Process.kill(#{signal.dump}, Process.pid)
    sleep
  RUBY
end

Given('Herdr terminates from signal {string} while reading the recorded pane') do |signal|
  install_fake_herdr(<<~RUBY)
    abort "unexpected arguments: \#{ARGV.join(' ')}" unless ARGV == %w[agent get w9:p1]
    Process.kill(#{signal.dump}, Process.pid)
    sleep
  RUBY
end

Given('Herdr terminates from signal {string} while sending the recorded interrupt key') do |signal|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get'] then puts #{pi_agent_response.dump}
    when ['pane', 'send-keys'] then Process.kill(#{signal.dump}, Process.pid); sleep
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr fails to read the recorded pane with status {int} and error {string}') do |status, error|
  install_fake_herdr(<<~RUBY)
    abort "unexpected arguments: \#{ARGV.join(' ')}" unless ARGV == %w[agent get w9:p1]
    warn #{error.dump}
    exit #{status}
  RUBY
end

Given('Herdr fails to send the recorded interrupt key with status {int} and error {string}') do |status, error|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get'] then puts #{pi_agent_response.dump}
    when ['pane', 'send-keys'] then warn #{error.dump}; exit #{status}
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr cannot re-read the recorded pane after the key with status {int} and error {string}') do |status, error|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get']
      if File.readlines(File.expand_path('invocations', __dir__)).length == 1
        puts #{pi_agent_response.dump}
      else
        warn #{error.dump}
        exit #{status}
      end
    when ['pane', 'send-keys'] then nil
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr reports the recorded pane hosting {string} after the key') do |kind|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get']
      first = File.readlines(File.expand_path('invocations', __dir__)).length == 1
      puts(first ? #{pi_agent_response.dump} : #{pi_agent_response(kind: kind).dump})
    when ['pane', 'send-keys'] then nil
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr reports pane {string} for the recorded pane after the key') do |other|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get']
      first = File.readlines(File.expand_path('invocations', __dir__)).length == 1
      puts(first ? #{pi_agent_response.dump} : #{pi_agent_response(pane_id: other).dump})
    when ['pane', 'send-keys'] then nil
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr returns malformed JSON when reading the recorded pane') do
  install_fake_herdr(<<~RUBY)
    abort "unexpected arguments: \#{ARGV.join(' ')}" unless ARGV == %w[agent get w9:p1]
    puts 'not JSON'
  RUBY
end

Given('Herdr replies to the recorded pane re-read with malformed JSON') do
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get']
      first = File.readlines(File.expand_path('invocations', __dir__)).length == 1
      puts(first ? #{pi_agent_response.dump} : 'not JSON')
    when ['pane', 'send-keys'] then nil
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr verifies inherited ownership of the lock after killing the interrupt controller for {string}') do |name|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get'] then puts #{pi_agent_response.dump}
    when ['pane', 'send-keys']
      controller = Process.ppid
      Process.kill('KILL', controller)
      100.times do
        break if Process.ppid != controller
        sleep 0.01
      end
      abort 'interrupt controller did not exit' if Process.ppid == controller
      path = File.join(ENV.fetch('RIDDIM_STATE_DIR'), ".meta-#{name}.lock")
      inherited = File.open(path, File::RDWR) { |lock| !lock.flock(File::LOCK_EX | File::LOCK_NB) }
      abort 'Herdr subprocess did not inherit the per-name lock' unless inherited
      File.write(File.expand_path('inherited-lock-held', __dir__), 'yes')
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr verifies the per-name lock while interrupting {string}') do |name|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get'] then puts #{pi_agent_response.dump}
    when ['pane', 'send-keys']
      path = File.join(ENV.fetch('RIDDIM_STATE_DIR'), ".meta-#{name}.lock")
      File.open(path, File::RDWR) do |lock|
        abort 'per-name lock was not held during interrupt' if lock.flock(File::LOCK_EX | File::LOCK_NB)
      end
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Then('Herdr receives {string} then {string} then {string}') do |first, second, third|
  assert_equal [first, second, third], herdr_invocations
end

Then('the command preserves signal {string}, output {string}, and error {string}') do |signal, output, error|
  actual = [@status.termsig, @stdout, @stderr]
  expected = [Signal.list.fetch(signal), "#{output}\n", "#{error}\n"]

  assert_equal expected, actual
end

Then('the Herdr child retained the per-name lock after its controller exited') do
  marker = File.join(@herdr_directory, 'inherited-lock-held')
  observed = 100.times.any? do
    found = File.exist?(marker)
    sleep 0.01 unless found
    found
  end

  assert observed
end

Then('the inherited per-name lock for {string} eventually becomes available') do |name|
  path = File.join(scenario_state_dir, ".meta-#{name}.lock")
  available = 100.times.any? do
    acquired = File.open(path, File::RDWR) { |file| file.flock(File::LOCK_EX | File::LOCK_NB) }
    sleep 0.01 unless acquired
    acquired
  end

  assert available
end

Then('Herdr never sends an interrupt key') do
  assert_empty herdr_invocations.grep(/\Apane send-keys\b/)
end
