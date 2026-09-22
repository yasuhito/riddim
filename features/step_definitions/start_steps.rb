# frozen_string_literal: true

require 'json'

# The canned Herdr workspace-create response shared by the start fakes.
CANNED_CREATE_RESPONSE = JSON.generate(
  id: 'cli:workspace:create',
  result: {
    type: 'workspace_created',
    workspace: { workspace_id: 'w9', label: 'riddim-worker' },
    tab: { tab_id: 'w9:t1', workspace_id: 'w9', label: '1' },
    root_pane: { pane_id: 'w9:p1', workspace_id: 'w9', tab_id: 'w9:t1', cwd: Dir.pwd }
  }
).freeze

Given('a Herdr executable that refuses every invocation') do
  install_fake_herdr(<<~RUBY)
    abort "unexpected invocation: \#{ARGV.join(' ')}"
  RUBY
end

Given('a config directory with agent profile:') do |content|
  directory = new_temporary_directory
  File.write(File.join(directory, 'agent-profile'), content)
  @environment = (@environment || {}).merge('RIDDIM_CONFIG_DIR' => directory)
end

Given('a config directory with a profile whose model contains a control character') do
  directory = new_temporary_directory
  File.write(File.join(directory, 'agent-profile'), "pi mo\x00del max\n")
  @environment = (@environment || {}).merge('RIDDIM_CONFIG_DIR' => directory)
end

Given('no agent profile in the config directory') do
  @environment = (@environment || {}).merge('RIDDIM_CONFIG_DIR' => new_temporary_directory)
end

Given('Herdr creates workspace {string} and starts the agent') do |_workspace_id|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2] when ['workspace', 'create'] then puts #{CANNED_CREATE_RESPONSE.dump} when ['agent', 'start'] then nil when ['pane', 'close'] then exit 0 else abort "unexpected command: \#{ARGV.join(' ')}" end
  RUBY
end

Given('Herdr replies to the workspace create with:') do |body|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2] when ['workspace', 'create'] then puts #{body.dump} else abort "unexpected command: \#{ARGV.join(' ')}" end
  RUBY
end

Given('Herdr refuses to create a workspace with status {int} and error {string}') do |status, error|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2] when ['workspace', 'create'] then warn #{error.dump}; exit #{status} else abort "unexpected command: \#{ARGV.join(' ')}" end
  RUBY
end

Given('Herdr creates workspace {string} but fails to start the agent with ' \
      'status {int} and error {string}') do |_w, status, error|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2] when ['workspace', 'create'] then puts #{CANNED_CREATE_RESPONSE.dump} when ['agent', 'start'] then warn #{error.dump}; exit #{status} when ['pane', 'close'] then exit 0 else abort "unexpected command: \#{ARGV.join(' ')}" end
  RUBY
end

Given('Herdr creates workspace {string} but fails to start the agent with ' \
      'status {int} and error {string} and closes panes with status {int}') do |_w, status, error, close_status|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2] when ['workspace', 'create'] then puts #{CANNED_CREATE_RESPONSE.dump} when ['agent', 'start'] then warn #{error.dump}; exit #{status} when ['pane', 'close'] then exit #{close_status} else abort "unexpected command: \#{ARGV.join(' ')}" end
  RUBY
end

# The exact workspace-create and agent-start invocations for one session,
# each carrying the explicit --session flag ahead of its subcommand. The
# agent-start passthrough tail ends at --thinking, so nothing leaks into the
# Pi agent's own arguments.
def expected_start_invocations(session)
  [
    "--session #{session} workspace create --cwd #{Dir.pwd} --label riddim-worker --no-focus",
    "--session #{session} agent start worker --kind pi --pane w9:p1 -- " \
    '--model openrouter/z-ai/glm-5.3-flash --thinking max'
  ]
end

Then('Herdr receives no invocation') do
  assert_empty herdr_invocations
end

Then('Herdr never starts an agent') do
  assert_empty herdr_invocations.grep(/\Aagent start\b/)
end

Then('Herdr creates a workspace labeled {string} in the current directory without focus') do |label|
  assert_includes herdr_invocations,
                  "--session #{scenario_session} workspace create --cwd #{Dir.pwd} --label #{label} --no-focus"
end

Then('Herdr starts agent {string} in pane {string} with model {string} ' \
     'and effort {string}') do |name, pane, model, effort|
  assert_includes(
    herdr_invocations,
    "--session #{scenario_session} agent start #{name} --kind pi --pane #{pane} -- " \
    "--model #{model} --thinking #{effort}"
  )
end

Then('Herdr only creates the workspace and starts the agent') do
  assert_equal expected_start_invocations(scenario_session), herdr_invocations
end

Then('Herdr creates a workspace and starts the agent in session {string}') do |session|
  assert_equal expected_start_invocations(session), herdr_invocations
end

Then('Herdr closes only pane {string}') do |pane|
  assert_equal expected_start_invocations(scenario_session) + ["--session #{scenario_session} pane close #{pane}"],
               herdr_invocations
end

Then('Herdr closes only pane {string} in session {string}') do |pane, session|
  assert_equal expected_start_invocations(session) + ["--session #{session} pane close #{pane}"], herdr_invocations
end
