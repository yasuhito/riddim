# frozen_string_literal: true

Then('Herdr never creates a workspace') do
  assert_empty herdr_invocations.grep(/workspace create/)
end

Given('the Herdr client reports protocol {int}') do |protocol|
  status = JSON.generate(client: { protocol: protocol, version: '0.9.0' }, server: { running: false })
  File.write(File.join(@herdr_directory, 'client-status.json'), status)
end

Given('the running Herdr server reports version {string}') do |version|
  status = JSON.generate(client: { protocol: 22, version: '0.9.0' }, server: { running: true, version: version })
  File.write(File.join(@herdr_directory, 'client-status.json'), status)
end

Given('the Herdr client reports version {string}') do |version|
  status = JSON.generate(client: { protocol: 15, version: version }, server: { running: false })
  File.write(File.join(@herdr_directory, 'client-status.json'), status)
end

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

# Herdr's structured response for a pane get of a missing pane. Real clients
# exit nonzero for this business response, which the presence classifier must
# ignore in favor of the body.
PANE_NOT_FOUND_RESPONSE = JSON.generate(
  id: 'cli:pane:get',
  error: { code: 'pane_not_found', message: 'pane not found' }
).freeze

# Herdr's response for a pane get of a pane that still exists.
PANE_PRESENT_RESPONSE = JSON.generate(
  id: 'cli:pane:get',
  result: { type: 'pane_info', pane: { pane_id: 'w9:p1', workspace_id: 'w9', tab_id: 'w9:t1' } }
).freeze

Given('a Herdr executable that refuses every invocation') do
  install_fake_herdr(<<~RUBY)
    abort "unexpected invocation: \#{ARGV.join(' ')}"
  RUBY
end

Given('a config directory with agent profile:') do |content|
  directory = new_temporary_directory
  File.write(File.join(directory, 'agent-profile'), content)
  @environment = @environment.merge('RIDDIM_CONFIG_DIR' => directory)
end

Given('a config directory with a profile whose model contains a control character') do
  directory = new_temporary_directory
  File.write(File.join(directory, 'agent-profile'), "pi mo\x00del max\n")
  @environment = @environment.merge('RIDDIM_CONFIG_DIR' => directory)
end

Given('no agent profile in the config directory') do
  @environment = @environment.merge('RIDDIM_CONFIG_DIR' => new_temporary_directory)
end

Given('an existing endpoint record for {string} that is not a record') do |name|
  FileUtils.mkdir_p(scenario_state_dir)
  File.write(scenario_record_path(name), "spawn_gen=s1\nnot a record\n")
end

Given('Herdr creates workspace {string} and starts the agent') do |_workspace_id|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['workspace', 'create'] then puts #{CANNED_CREATE_RESPONSE.dump}
    when ['agent', 'start'] then nil
    else abort "unexpected command: \#{ARGV.join(' ')}"
    end
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
    case ARGV[0, 2]
    when ['workspace', 'create'] then puts #{CANNED_CREATE_RESPONSE.dump}
    when ['agent', 'start'] then warn #{error.dump}; exit #{status}
    when ['pane', 'close'] then exit 0
    when ['pane', 'get'] then puts #{PANE_NOT_FOUND_RESPONSE.dump}; exit 1
    else abort "unexpected command: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr creates workspace {string} but fails to start the agent with ' \
      'status {int} and error {string} and closes panes with status {int}') do |_w, status, error, close_status|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['workspace', 'create'] then puts #{CANNED_CREATE_RESPONSE.dump}
    when ['agent', 'start'] then warn #{error.dump}; exit #{status}
    when ['pane', 'close'] then warn 'herdr: cannot close pane'; exit #{close_status}
    else abort "unexpected command: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr creates workspace {string} but fails to start the agent with ' \
      'status {int} and error {string} and leaves the pane present') do |_w, status, error|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['workspace', 'create'] then puts #{CANNED_CREATE_RESPONSE.dump}
    when ['agent', 'start'] then warn #{error.dump}; exit #{status}
    when ['pane', 'close'] then exit 0
    when ['pane', 'get'] then puts #{PANE_PRESENT_RESPONSE.dump}
    else abort "unexpected command: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr creates workspace {string} but fails to start the agent with ' \
      'status {int} and error {string} and returns an ambiguous pane read') do |_w, status, error|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['workspace', 'create'] then puts #{CANNED_CREATE_RESPONSE.dump}
    when ['agent', 'start'] then warn #{error.dump}; exit #{status}
    when ['pane', 'close'] then exit 0
    when ['pane', 'get'] then puts 'not JSON'
    else abort "unexpected command: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr creates workspace {string} and then disappears') do |_w|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['workspace', 'create']
      puts #{CANNED_CREATE_RESPONSE.dump}
      File.delete($0)
    else abort "unexpected command: \#{ARGV.join(' ')}"
    end
  RUBY
  # Do not fall through to the real Herdr after the fake deletes itself.
  restrict_path_without_herdr(@herdr_directory)
end

Given('Herdr creates workspace {string} and refuses to start an agent before its record exists') do |_w|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['workspace', 'create'] then puts #{CANNED_CREATE_RESPONSE.dump}
    when ['agent', 'start']
      record = File.join(ENV.fetch('RIDDIM_STATE_DIR'), "\#{ARGV[2]}.meta")
      abort "agent start before the record was published: \#{record}" unless File.exist?(record)
    else abort "unexpected command: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr creates workspace {string} but another writer claims the record during creation') do |_w|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['workspace', 'create']
      puts #{CANNED_CREATE_RESPONSE.dump}
      File.write(File.join(ENV.fetch('RIDDIM_STATE_DIR'), 'worker.meta'), "claimed by another writer\\n")
    when ['pane', 'close'] then exit 0
    when ['pane', 'get'] then puts #{PANE_NOT_FOUND_RESPONSE.dump}; exit 1
    else abort "unexpected command: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr creates workspace {string} but another writer claims the record during creation ' \
      'and closes panes with status {int}') do |_w, close_status|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['workspace', 'create']
      puts #{CANNED_CREATE_RESPONSE.dump}
      File.write(File.join(ENV.fetch('RIDDIM_STATE_DIR'), 'worker.meta'), "claimed by another writer\\n")
    when ['pane', 'close'] then warn 'herdr: cannot close pane'; exit #{close_status}
    else abort "unexpected command: \#{ARGV.join(' ')}"
    end
  RUBY
end

# The exact session-targeted invocations of one start, each carrying the
# explicit --session flag ahead of its subcommand. The agent-start passthrough
# tail ends at --thinking, so nothing leaks into the Pi agent's own arguments.
def workspace_create_invocation(session)
  "--session #{session} workspace create --cwd #{Dir.pwd} --label riddim-worker --no-focus"
end

def agent_start_invocation(session)
  "--session #{session} agent start worker --kind pi --pane w9:p1 -- " \
    '--model openrouter/z-ai/glm-5.3-flash --thinking max'
end

def pane_close_invocation(session, pane)
  "--session #{session} pane close #{pane}"
end

def pane_get_invocation(session, pane)
  "--session #{session} pane get #{pane}"
end

def expected_start_invocations(session)
  [workspace_create_invocation(session), agent_start_invocation(session)]
end

# The published endpoint ownership record, with the one value a scenario
# cannot predict - the minted spawn generation - masked to a placeholder.
def masked_record(name)
  File.read(scenario_record_path(name)).sub(/^spawn_gen=.*$/, 'spawn_gen=<spawn_gen>')
end

Then('Herdr receives no invocation') do
  assert_empty herdr_invocations
end

Then('Herdr never starts an agent') do
  assert_empty herdr_invocations.grep(/\bagent start\b/)
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

Then('Herdr closes and re-reads only pane {string}') do |pane|
  assert_equal expected_start_invocations(scenario_session) +
               [pane_close_invocation(scenario_session, pane), pane_get_invocation(scenario_session, pane)],
               herdr_invocations
end

Then('Herdr closes and re-reads only pane {string} in session {string}') do |pane, session|
  assert_equal expected_start_invocations(session) +
               [pane_close_invocation(session, pane), pane_get_invocation(session, pane)],
               herdr_invocations
end

Then('Herdr creates only the workspace and then closes and re-reads pane {string}') do |pane|
  assert_equal [workspace_create_invocation(scenario_session),
                pane_close_invocation(scenario_session, pane),
                pane_get_invocation(scenario_session, pane)],
               herdr_invocations
end

Then('Herdr closes pane {string} without a follow-up pane read') do |pane|
  assert_equal expected_start_invocations(scenario_session) + [pane_close_invocation(scenario_session, pane)],
               herdr_invocations
end

Then('Herdr closes the created pane {string} without a follow-up pane read') do |pane|
  assert_equal [workspace_create_invocation(scenario_session), pane_close_invocation(scenario_session, pane)],
               herdr_invocations
end

Then('the endpoint record for {string} is:') do |name, bytes|
  assert_equal "#{bytes}\n", masked_record(name)
end

Then('the endpoint record for {string} still is:') do |name, bytes|
  assert_equal "#{bytes}\n", File.read(scenario_record_path(name))
end

Then('the endpoint record for {string} records a fresh spawn generation') do |name|
  line = File.readlines(scenario_record_path(name)).find { |entry| entry.start_with?('spawn_gen=') }

  assert_match(/\Aspawn_gen=s\d+\.\d+\.\d+\n\z/, line)
end

Then('the endpoint record for {string} is readable only by its owner') do |name|
  assert_equal 0o600, File.stat(scenario_record_path(name)).mode & 0o777
end

Then('the state directory is readable only by its owner') do
  assert_equal 0o700, File.stat(scenario_state_dir).mode & 0o777
end

Then('only the record and its per-name lock remain in the state directory') do
  assert_equal ['.meta-worker.lock', 'worker.meta'], Dir.children(scenario_state_dir).sort
end

Then('the endpoint record for {string} does not exist') do |name|
  path = scenario_record_path(name)

  refute(File.exist?(path) || File.symlink?(path), "expected no endpoint record at #{path}")
end

Then('the endpoint record for {string} remains') do |name|
  path = scenario_record_path(name)

  assert(File.exist?(path) || File.symlink?(path), "expected the endpoint record to remain at #{path}")
end

Then('the duplicate endpoint record refusal is explained for {string}') do |name|
  assert_equal(
    "riddim: refusing to start #{name}: an endpoint record already exists at #{scenario_record_path(name)}\n",
    @stderr
  )
end

Then('the publication refusal and the confirmed cleanup are reported for {string}') do |name|
  assert_equal(<<~ERROR, @stderr)
    riddim: an endpoint record already exists at #{scenario_record_path(name)}
    riddim: cleanup confirmed: session #{scenario_session} workspace w9 tab w9:t1 pane w9:p1 was closed and confirmed gone
  ERROR
end

Then('the publication refusal and the unconfirmed cleanup are reported for {string}') do |name|
  assert_equal(<<~ERROR, @stderr)
    riddim: an endpoint record already exists at #{scenario_record_path(name)}
    riddim: cleanup unconfirmed: session #{scenario_session} workspace w9 tab w9:t1 pane w9:p1 may still exist
  ERROR
end

Then("Herdr's failure and the retained record are reported for {string}") do |name|
  assert_equal(<<~ERROR, @stderr)
    herdr: agent not ready
    riddim: the endpoint record for #{name} is retained at #{scenario_record_path(name)}: the created pane was not confirmed closed (session #{scenario_session} workspace w9 tab w9:t1 pane w9:p1); it may still exist
  ERROR
end

Then('the unlaunchable Herdr failure and the retained record are reported for {string}') do |name|
  assert_equal(<<~ERROR, @stderr)
    riddim: No such file or directory - herdr
    riddim: the endpoint record for #{name} is retained at #{scenario_record_path(name)}: the created pane was not confirmed closed (session #{scenario_session} workspace w9 tab w9:t1 pane w9:p1); it may still exist
  ERROR
end

Then('Herdr closes no pane without a Herdr executable') do
  assert_equal [workspace_create_invocation(scenario_session)], herdr_invocations
end

Then('exactly one of the two starts succeeds') do
  successes = @concurrent_starts.count { |_stdout, _stderr, status| status.success? }

  assert_equal 1, successes
end

Then('the losing start refuses the duplicate for {string}') do |name|
  loser = @concurrent_starts.reject { |_stdout, _stderr, status| status.success? }.first

  assert_equal(
    "riddim: refusing to start #{name}: an endpoint record already exists at #{scenario_record_path(name)}\n",
    loser[1]
  )
end

Then('Herdr creates the workspace exactly once') do
  assert_equal 1, herdr_invocations.grep(/\bworkspace create\b/).length
end

Then('Herdr starts exactly one agent') do
  assert_equal 1, herdr_invocations.grep(/\bagent start\b/).length
end
