# frozen_string_literal: true

require 'json'

# Builds one canned `herdr agent get` response for a Pi-like agent.
def pi_agent_response(kind: 'pi', pane_id: 'w9:p1', status: 'working')
  agent = { agent: kind, agent_status: status }
  agent[:pane_id] = pane_id unless pane_id.nil?
  JSON.generate(id: 'cli:agent:get', result: { type: 'agent_info', agent: agent })
end

# Resolves the agent by name or pane id and accepts the interrupt key.
Given('Herdr resolves pi to pane {string} and accepts the interrupt key') do |pane|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get'] then puts #{pi_agent_response(pane_id: pane).dump}
    when ['agent', 'send-keys'] then nil
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr resolves pi to pane {string} hosting {string}') do |pane, kind|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get'] then puts #{pi_agent_response(kind: kind, pane_id: pane).dump}
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr resolves pi without a pane id') do
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get'] then puts #{pi_agent_response(pane_id: nil).dump}
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr fails to send the interrupt key with status {int} and error {string}') do |status, error|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get'] then puts #{pi_agent_response.dump}
    when ['agent', 'send-keys'] then warn #{error.dump}; exit #{status}
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr cannot re-read pane {string} after the key with status {int} and error {string}') do |_pane, status, error|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get']
      if ARGV[2] == 'pi'
        puts #{pi_agent_response.dump}
      else
        warn #{error.dump}
        exit #{status}
      end
    when ['agent', 'send-keys'] then nil
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr reports pane {string} hosting {string} after the key') do |pane, kind|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get']
      if ARGV[2] == 'pi'
        puts #{pi_agent_response.dump}
      else
        puts #{pi_agent_response(kind: kind, pane_id: pane).dump}
      end
    when ['agent', 'send-keys'] then nil
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr reports pane {string} in pane {string} after the key') do |_pane, other|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get']
      if ARGV[2] == 'pi'
        puts #{pi_agent_response.dump}
      else
        puts #{pi_agent_response(pane_id: other).dump}
      end
    when ['agent', 'send-keys'] then nil
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr replies to the pane re-read with malformed JSON') do
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['agent', 'get']
      if ARGV[2] == 'pi'
        puts #{pi_agent_response.dump}
      else
        puts 'not JSON'
      end
    when ['agent', 'send-keys'] then nil
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Then('Herdr receives {string} then {string} then {string}') do |first, second, third|
  assert_equal [first, second, third], herdr_invocations
end

Then('Herdr never sends an interrupt key') do
  assert_empty herdr_invocations.grep(/\Aagent send-keys\b/)
end
