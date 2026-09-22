# frozen_string_literal: true

require 'fileutils'
require_relative '../../lib/riddim/ownership'

# The fields every ownership-routed scenario's record shares; only the
# endpoint a scenario wants the command to address varies.
OWNERSHIP_RECORD_BASE = {
  'harness' => 'pi',
  'model' => 'openrouter/z-ai/glm-5.3-flash',
  'effort' => 'max',
  'spawn_gen' => 's1767200000.4242.7',
  'backend' => 'herdr',
  'herdr_workspace_id' => 'w9',
  'herdr_tab_id' => 'w9:t1'
}.freeze

# The fields of one published endpoint record as acceptance scenarios write
# them: the same Firstmate-shaped record `riddim start` publishes, bound to
# the endpoint a scenario wants a command to address.
def ownership_record_fields(name, session:, pane_id: 'w9:p1', overrides: {})
  OWNERSHIP_RECORD_BASE.merge(
    'window' => "#{session}:#{pane_id}", 'endpoint_task_id' => name, 'herdr_session' => session,
    'herdr_pane_id' => pane_id
  ).merge(overrides)
end

# Writes a complete record into the scenario's isolated state directory.
def publish_record(name, **)
  FileUtils.mkdir_p(scenario_state_dir)
  fields = ownership_record_fields(name, **)
  File.write(scenario_record_path(name), Riddim::Ownership.serialize(fields))
end

Given('a published endpoint record for {string} in session {string} naming pane {string}') do |name, session, pane|
  publish_record(name, session: session, pane_id: pane)
end

Given('an endpoint record for {string} that is not valid UTF-8') do |name|
  FileUtils.mkdir_p(scenario_state_dir)
  File.binwrite(scenario_record_path(name), "\xFF\n".b)
end

Given('an endpoint record for {string} with a malformed Herdr session') do |name|
  publish_record(name, session: 'bad session')
end

Given('an endpoint record for {string} whose window names another pane') do |name|
  publish_record(name, session: 'riddim', pane_id: 'w9:p1', overrides: { 'window' => 'riddim:w9:p2' })
end

Then('the invalid UTF-8 record refusal is explained for {string}') do |name|
  expected = "riddim: the endpoint record for #{name} at #{scenario_record_path(name)} " \
             "is unreadable: an endpoint record must use valid UTF-8\n"
  assert_equal expected, @stderr
end

Given('a symlinked endpoint record for {string} that points elsewhere') do |name|
  FileUtils.mkdir_p(scenario_state_dir)
  target = File.join(new_temporary_directory, 'elsewhere.meta')
  fields = ownership_record_fields(name, session: 'riddim')
  File.write(target, Riddim::Ownership.serialize(fields))
  File.symlink(target, scenario_record_path(name))
end
