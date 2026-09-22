# frozen_string_literal: true

require 'fileutils'
require_relative '../../lib/riddim/ownership'

# The fields every peek scenario's record shares; only the endpoint a
# scenario wants peek to capture varies.
PEEK_RECORD_BASE = {
  'harness' => 'pi',
  'model' => 'openrouter/z-ai/glm-5.3-flash',
  'effort' => 'max',
  'spawn_gen' => 's1767200000.4242.7',
  'backend' => 'herdr',
  'herdr_workspace_id' => 'w9',
  'herdr_tab_id' => 'w9:t1'
}.freeze

# The fields of one published endpoint record as the peek scenarios write
# them: the same Firstmate-shaped record `riddim start` publishes, bound to
# the endpoint a scenario wants peek to capture.
def peek_record_fields(name, session:, pane_id: 'w9:p1', overrides: {})
  PEEK_RECORD_BASE.merge(
    'window' => "#{session}:#{pane_id}", 'endpoint_task_id' => name, 'herdr_session' => session,
    'herdr_pane_id' => pane_id
  ).merge(overrides)
end

# Writes a complete record into the scenario's state directory.
def publish_record(name, **)
  FileUtils.mkdir_p(scenario_state_dir)
  File.write(scenario_record_path(name), Riddim::Ownership.serialize(peek_record_fields(name, **)))
end

Given('a published endpoint record for {string} in session {string} naming pane {string}') do |name, session, pane|
  publish_record(name, session: session, pane_id: pane)
end

Given('an endpoint record for {string} with a malformed Herdr session') do |name|
  publish_record(name, session: 'bad session')
end

Given('an endpoint record for {string} whose window names another pane') do |name|
  publish_record(name, session: 'riddim', pane_id: 'w9:p1', overrides: { 'window' => 'riddim:w9:p2' })
end

Given('a symlinked endpoint record for {string} that points elsewhere') do |name|
  FileUtils.mkdir_p(scenario_state_dir)
  target = File.join(new_temporary_directory, 'elsewhere.meta')
  File.write(target, Riddim::Ownership.serialize(peek_record_fields(name, session: 'riddim')))
  File.symlink(target, scenario_record_path(name))
end

Given('a Herdr executable that answers a pane read with 250 lines') do
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['pane', 'read'] then puts (1..250).map { |number| format('pane-%03d', number) }
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr fails the pane read with status {int} and error {string}') do |status, error|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['pane', 'read'] then puts 'partial tail'; warn #{error.dump}; exit #{status}
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

# The fake answers a pane read with 250 numbered lines, so a passing tail
# must be exactly the final <count> of them, trimmed in Riddim itself.
Then('standard output is the final {int} lines of the pane read') do |count|
  total = 250
  expected = ((total - count + 1)..total).map { |number| format('pane-%03d', number) }

  assert_equal "#{expected.join("\n")}\n", @stdout
end

Then('the missing record refusal is explained for {string}') do |name|
  assert_equal "riddim: no endpoint record exists at #{scenario_record_path(name)}\n", @stderr
end

Then('the unreadable record refusal is explained for {string}') do |name|
  reason = 'unreadable endpoint record line "not a record"'
  expected = "riddim: the endpoint record for #{name} at #{scenario_record_path(name)} is unreadable: #{reason}\n"

  assert_equal expected, @stderr
end

Then('the symlinked record refusal is explained for {string}') do |name|
  assert_equal "riddim: the endpoint record at #{scenario_record_path(name)} is a symbolic link\n", @stderr
end

Then('the inconsistent window refusal is explained for {string}') do |name|
  expected = "riddim: the endpoint record for #{name} records window \"riddim:w9:p2\", not \"riddim:w9:p1\"\n"

  assert_equal expected, @stderr
end
