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

# Appends one line per Herdr invocation to a log beside the fake executable.
LOG_INVOCATION = "File.open(File.expand_path('invocations', __dir__), 'a') { |file| file.puts ARGV.join(' ') }"

Given('a Herdr executable that refuses every invocation') do
  install_fake_herdr(<<~RUBY)
    #{LOG_INVOCATION}
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
    #{LOG_INVOCATION}
    case ARGV[0, 2] when ['workspace', 'create'] then puts #{CANNED_CREATE_RESPONSE.dump} when ['agent', 'start'] then nil when ['pane', 'close'] then exit 0 else abort "unexpected command: \#{ARGV.join(' ')}" end
  RUBY
end

Given('Herdr replies to the workspace create with:') do |body|
  install_fake_herdr(<<~RUBY)
    #{LOG_INVOCATION}
    case ARGV[0, 2] when ['workspace', 'create'] then puts #{body.dump} else abort "unexpected command: \#{ARGV.join(' ')}" end
  RUBY
end

Given('Herdr refuses to create a workspace with status {int} and error {string}') do |status, error|
  install_fake_herdr(<<~RUBY)
    #{LOG_INVOCATION}
    case ARGV[0, 2] when ['workspace', 'create'] then warn #{error.dump}; exit #{status} else abort "unexpected command: \#{ARGV.join(' ')}" end
  RUBY
end

Given('Herdr creates workspace {string} but fails to start the agent with ' \
      'status {int} and error {string}') do |_w, status, error|
  install_fake_herdr(<<~RUBY)
    #{LOG_INVOCATION}
    case ARGV[0, 2] when ['workspace', 'create'] then puts #{CANNED_CREATE_RESPONSE.dump} when ['agent', 'start'] then warn #{error.dump}; exit #{status} when ['pane', 'close'] then exit 0 else abort "unexpected command: \#{ARGV.join(' ')}" end
  RUBY
end

Given('Herdr creates workspace {string} but fails to start the agent with ' \
      'status {int} and error {string} and closes panes with status {int}') do |_w, status, error, close_status|
  install_fake_herdr(<<~RUBY)
    #{LOG_INVOCATION}
    case ARGV[0, 2] when ['workspace', 'create'] then puts #{CANNED_CREATE_RESPONSE.dump} when ['agent', 'start'] then warn #{error.dump}; exit #{status} when ['pane', 'close'] then exit #{close_status} else abort "unexpected command: \#{ARGV.join(' ')}" end
  RUBY
end

# Every Herdr invocation the fake executable observed, in order.
def herdr_invocations
  log = File.join(@herdr_directory, 'invocations')
  File.exist?(log) ? File.read(log).split("\n").reject(&:empty?) : []
end

Then('Herdr receives no invocation') do
  assert_empty herdr_invocations
end

Then('Herdr never starts an agent') do
  assert_empty herdr_invocations.grep(/\Aagent start\b/)
end

Then('Herdr creates a workspace labeled {string} in the current directory without focus') do |label|
  assert_includes herdr_invocations, "workspace create --cwd #{Dir.pwd} --label #{label} --no-focus"
end

Then('Herdr starts agent {string} in pane {string} with model {string} ' \
     'and effort {string}') do |name, pane, model, effort|
  assert_includes(
    herdr_invocations,
    "agent start #{name} --kind pi --pane #{pane} -- --model #{model} --thinking #{effort}"
  )
end

Then('Herdr only creates the workspace and starts the agent') do
  expected = [
    "workspace create --cwd #{Dir.pwd} --label riddim-worker --no-focus",
    'agent start worker --kind pi --pane w9:p1 -- --model openrouter/z-ai/glm-5.3-flash --thinking max'
  ]

  assert_equal expected, herdr_invocations
end

Then('Herdr closes only pane {string}') do |pane|
  expected = [
    "workspace create --cwd #{Dir.pwd} --label riddim-worker --no-focus",
    'agent start worker --kind pi --pane w9:p1 -- --model openrouter/z-ai/glm-5.3-flash --thinking max',
    "pane close #{pane}"
  ]

  assert_equal expected, herdr_invocations
end
