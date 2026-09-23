# frozen_string_literal: true

require 'fileutils'
require 'json'

# The pane-get responses the exit fake serves: present, or pane_not_found.
EXIT_PANE_PRESENT = JSON.generate(
  id: 'cli:pane:get', result: { type: 'pane_info', pane: { pane_id: 'w9:p1', workspace_id: 'w9', tab_id: 'w9:t1' } }
).freeze
EXIT_PANE_GONE = JSON.generate(
  id: 'cli:pane:get', error: { code: 'pane_not_found', message: 'pane not found' }
).freeze

# The exit-flow Herdr test double: marker files drive the agent state, the
# composer screens, and what one Enter submits.
#
#   no-agent      - the pane has no Pi registration (agent not found)
#   pane-gone     - pane get answers pane_not_found
#   mid-turn      - the registration reads working until one Escape lands
#   interrupted   - written by the fake when Escape is delivered (idle)
#   typed         - the composer visibly holds the typed line
#   swallowed     - one Enter is swallowed; the composer keeps its text
#   submitted     - the exit command was submitted once
#   never-stops   - the agent keeps reading alive even after submission
#   send-fails    - the literal send fails
EXIT_FAKE = <<~RUBY.freeze
  require 'json'
  case ARGV[0, 2]
  when ['pane', 'get']
    if File.exist?(File.expand_path('pane-gone', __dir__))
      warn #{EXIT_PANE_GONE.dump}
      exit 1
    end
    print #{EXIT_PANE_PRESENT.dump}
    exit 0
  when ['agent', 'get']
    if File.exist?(File.expand_path('no-agent', __dir__)) ||
       (File.exist?(File.expand_path('submitted', __dir__)) &&
        !File.exist?(File.expand_path('never-stops', __dir__)))
      puts JSON.generate(id: 'cli:agent:get', error: { code: 'agent_not_found', message: 'no agent' })
      exit 0
    end
    status = if File.exist?(File.expand_path('mid-turn', __dir__)) &&
                !File.exist?(File.expand_path('interrupted', __dir__))
               'working'
             else
               'idle'
             end
    puts JSON.generate(id: 'cli:agent:get', result: { type: 'agent_info', agent: { agent: 'pi', agent_status: status, pane_id: 'w9:p1' } })
    exit 0
  when ['pane', 'process-info']
    #{PROCESS_INFO_FIXTURE}
    exit 0
  when ['pane', 'read']
    rule = '─' * 12
    if File.exist?(File.expand_path('no-pair', __dir__))
      print "shell prompt\nplain output\n"
    elsif File.exist?(File.expand_path('typed', __dir__)) && !File.exist?(File.expand_path('submitted', __dir__))
      print rule + "\n/quit\n" + rule + "\n"
    else
      print rule + "\n\n" + rule + "\n"
    end
    exit 0
  when ['pane', 'send-text']
    if File.exist?(File.expand_path('send-fails', __dir__))
      warn 'herdr: send failed'
      exit 1
    end
    exit 0
  when ['pane', 'send-keys']
    if ARGV[3] == 'enter'
      swallowed = File.expand_path('swallowed', __dir__)
      if File.exist?(swallowed)
        File.delete(swallowed)
      else
        File.write(File.expand_path('submitted', __dir__), '')
      end
    elsif ARGV[3] == 'escape'
      File.write(File.expand_path('interrupted', __dir__), '')
    end
    exit 0
  else abort "unexpected invocation: \#{ARGV.join(' ')}"
  end
RUBY

Given('Herdr serves an exit flow') do
  install_fake_herdr(EXIT_FAKE)
end

Given('the pane has no Pi registration') do
  File.write(File.join(@herdr_directory, 'no-agent'), '')
end

Given('the recorded pane is gone') do
  File.write(File.join(@herdr_directory, 'pane-gone'), '')
end

Given('the pane is mid-turn') do
  File.write(File.join(@herdr_directory, 'mid-turn'), '')
end

Given('Herdr serves pending composer text') do
  File.write(File.join(@herdr_directory, 'typed'), '')
end

Given('Herdr serves an unprovable composer') do
  File.write(File.join(@herdr_directory, 'no-pair'), '')
end

Given('the exit command was submitted once') do
  File.write(File.join(@herdr_directory, 'submitted'), '')
end

Given('one Enter is swallowed before the submit lands') do
  File.write(File.join(@herdr_directory, 'swallowed'), '')
end

Given('the literal send fails') do
  File.write(File.join(@herdr_directory, 'send-fails'), '')
end

Given('the agent never stops after submission') do
  File.write(File.join(@herdr_directory, 'never-stops'), '')
end

Given('the exit wait is bounded to {string} seconds') do |seconds|
  @environment = (@environment || {}).merge('RIDDIM_EXIT_WAIT' => seconds)
end

Then('Herdr types the exit command exactly once') do
  typed = herdr_invocations.grep(/pane send-text/)

  assert_equal ['--session riddim pane send-text w9:p1 /quit'], typed
end

Then('Herdr types nothing into the pane') do
  assert_empty herdr_invocations.grep(/pane send-(text|keys)/)
end

Then('Herdr submits with Enter') do
  assert(herdr_invocations.any? { |invocation| invocation.end_with?('pane send-keys w9:p1 enter') })
end

Then('the interrupt key lands before the exit command') do
  order = herdr_invocations.map { |invocation| invocation.split[2, 2].join(' ') }
  escape = order.index('pane send-keys')
  literal = order.index('pane send-text')

  assert escape, 'no interrupt key was delivered'
  assert literal, 'no exit command was typed'
  assert_operator escape, :<, literal
end
