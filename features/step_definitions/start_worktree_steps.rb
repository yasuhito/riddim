# frozen_string_literal: true

require 'json'
require 'open3'

Given('a local Git project for worktree start') do
  @project = File.join(new_temporary_directory, 'project')
  Dir.mkdir(@project)
  git = ->(*args) { Open3.capture3('git', '-C', @project, *args) }
  raise 'git init failed' unless git.call('init', '-q').last.success?

  # Linked worktrees share this fixture's identity, including later dirty commits.
  { 'user.name' => 'Riddim', 'user.email' => 'test@example.invalid' }.each do |key, value|
    raise 'git identity config failed' unless git.call('config', '--local', key, value).last.success?
  end

  File.write(File.join(@project, 'tracked.txt'), "base\n")
  raise 'git add failed' unless git.call('add', 'tracked.txt').last.success?
  raise 'git commit failed' unless git.call('-c', 'user.name=Riddim', '-c', 'user.email=test@example.invalid',
                                            'commit', '-qm', 'base').last.success?

  @worktree = File.join(File.dirname(@project), 'project-riddim-worker')
  @working_directory = @project
end

Given('the project contains a Pi extension') do
  extension = File.join(@project, '.pi', 'extensions', 'test.ts')
  FileUtils.mkdir_p(File.dirname(extension))
  File.write(extension, 'export default function test() {}')
  git = ->(*args) { Open3.capture3('git', '-C', @project, *args) }
  raise 'extension git add failed' unless git.call('add', '.pi/extensions').last.success?
  raise 'extension commit failed' unless git.call('-c', 'user.name=Riddim', '-c', 'user.email=test@example.invalid',
                                                  'commit', '-qm', 'Pi extension').last.success?
end

def configure_pi_agent_directory(contents)
  @pi_agent_directory = File.join(new_temporary_directory, 'pi-agent')
  FileUtils.mkdir_p(@pi_agent_directory, mode: 0o700)
  File.chmod(0o700, @pi_agent_directory)
  @pi_trust_file = File.join(@pi_agent_directory, 'trust.json')
  File.write(@pi_trust_file, contents)
  File.chmod(0o600, @pi_trust_file)
  @environment['PI_CODING_AGENT_DIR'] = @pi_agent_directory
end

Given('the Pi trust store contains a denial for the worktree parent') do
  configure_pi_agent_directory(JSON.generate(File.dirname(@worktree) => false, '/unrelated-project' => true))
end

Given('the Pi trust store contains invalid data') do
  configure_pi_agent_directory('[]')
end

Given('the Pi trust store directory does not exist') do
  @pi_agent_directory = File.join(new_temporary_directory, 'pi-agent')
  @pi_trust_file = File.join(@pi_agent_directory, 'trust.json')
  @environment['PI_CODING_AGENT_DIR'] = @pi_agent_directory
end

Given('Herdr checks Pi trust before creating a workspace') do
  File.write(File.join(@herdr_directory, 'check-pi-trust-before-workspace'), '')
end

Given('the project contains the Riddim CLI') do
  FileUtils.mkdir_p(File.join(@project, 'bin'))
  FileUtils.cp(RiddimWorld::RIDDIM, File.join(@project, 'bin', 'riddim'))
  source_lib = File.join(File.dirname(RiddimWorld::RIDDIM, 2), 'lib')
  FileUtils.cp_r(source_lib, @project)
  git = ->(*args) { Open3.capture3('git', '-C', @project, *args) }
  raise 'git add failed' unless git.call('add', 'bin', 'lib').last.success?
  raise 'git commit failed' unless git.call('-c', 'user.name=Riddim', '-c', 'user.email=test@example.invalid',
                                            'commit', '-qm', 'riddim sources').last.success?
end

Given('the project has an earlier commit and a post-checkout hook resets the worker branch') do
  git = ->(*args) { Open3.capture3('git', '-C', @project, *args) }
  raise 'second commit failed' unless git.call('-c', 'user.name=Riddim', '-c', 'user.email=test@example.invalid',
                                               'commit', '--allow-empty', '-qm', 'second').last.success?

  hook = File.join(@project, '.git', 'hooks', 'post-checkout')
  File.write(hook, "#!/bin/sh\ngit reset --hard -q HEAD~1\n")
  File.chmod(0o755, hook)
end

WORKTREE_AGENT_START = <<~RUBY
  abort 'agent arguments cannot be encoded safely for the target shell' if ARGV.any? { |arg| arg.include?(10.chr) }
  if ARGV.last != 'max'
    brief = File.join(ENV.fetch('RIDDIM_STATE_DIR'), 'worker.brief')
    abort 'agent start before the task brief was published' unless File.file?(brief)
    File.binwrite(File.expand_path('initial-brief', __dir__), ARGV.last)
  end
  if File.exist?(File.expand_path('agent-start-fails', __dir__))
    warn 'agent refused start'
    exit 7
  end
RUBY

WORKTREE_PI_TRUST_CHECK = <<~RUBY
  if File.file?(File.expand_path('check-pi-trust-before-workspace', __dir__))
    trust = JSON.parse(File.read(File.join(ENV.fetch('PI_CODING_AGENT_DIR'), 'trust.json')))
    abort 'Pi worktree trust was not registered before workspace creation' unless trust[cwd] == true
  end
RUBY

WORKTREE_TASK_LAUNCH = <<~RUBY
  when ['pane', 'run']
    abort 'wrong pane' unless ARGV[2] == 'w9:p1'
    command = ARGV[3]
    abort 'expected a sourced private launch file' unless command.start_with?('. ')
    script = command.delete_prefix('. ')
    abort 'record missing at shell submission' unless File.file?(File.join(ENV.fetch('RIDDIM_STATE_DIR'), 'worker.meta'))
    abort 'launch script missing or not private' unless File.file?(script) && File.stat(script).mode & 0o777 == 0o600
    File.binwrite(File.expand_path('staged-launch', __dir__), File.binread(script))
    if File.file?(File.expand_path('shell-submit-fails', __dir__))
      warn 'shell submission unconfirmed'
      exit 7
    end
    File.write(File.expand_path('launch-submitted', __dir__), '')
    if File.file?(File.expand_path('execute-task-launch', __dir__))
      cwd = File.read(File.expand_path('workspace-cwd', __dir__)).strip
      abort 'task launch failed' unless system('/bin/sh', '-c', command, chdir: cwd)
    end
    puts JSON.generate(result: { type: 'ok' })
  when ['pane', 'process-info']
    puts JSON.generate(result: { type: 'pane_process_info', process_info: {
      pane_id: 'w9:p1', shell_pid: Process.ppid,
      foreground_processes: [{ pid: Process.ppid, name: 'pi', argv: ['pi'] }] } })
  when ['agent', 'get']
    abort 'wrong agent target' unless ['w9:p1', 'worker'].include?(ARGV[2])
    abort 'agent get before launch' unless File.file?(File.expand_path('launch-submitted', __dir__))
    if File.exist?(File.expand_path('agent-gone', __dir__))
      puts JSON.generate(error: { code: 'agent_not_found' })
      exit 1
    end
    replacement = File.expand_path('replace-owner-on-probe', __dir__)
    if File.file?(replacement)
      field = File.read(replacement)
      record = File.join(ENV.fetch('RIDDIM_STATE_DIR'), 'worker.meta')
      File.write(record, File.read(record).sub(/^\#{field}=.*$/, "\#{field}=replacement"))
    end
    response = File.expand_path('teardown-agent.json', __dir__)
    if File.file?(response)
      puts File.read(response)
      exit 0
    end
    kind = File.file?(File.expand_path('unrecognized-pi', __dir__)) ? 'codex' : 'pi'
    name = File.file?(File.expand_path('agent-named', __dir__)) ? 'worker' : nil
    replaced = ARGV[2] == 'worker' && File.file?(File.expand_path('replaced-pi', __dir__))
    session = replaced ? '/tmp/replaced-session' : '/tmp/test-session'
    puts JSON.generate(result: { agent: { agent: kind, name: name, agent_status: 'working', pane_id: 'w9:p1',
                                          workspace_id: 'w9', tab_id: 'w9:t1',
                                          agent_session: { source: 'herdr:pi', kind: 'path', value: session } } })
  when ['agent', 'rename']
    abort 'wrong rename target' unless ARGV[2..] == ['w9:p1', 'worker']
    if File.file?(File.expand_path('rename-fails', __dir__))
      warn 'rename refused'
      exit 7
    end
    File.write(File.expand_path('agent-named', __dir__), '')
    puts JSON.generate(result: { agent: { agent: 'pi', name: 'worker', agent_status: 'working', pane_id: 'w9:p1',
                                          workspace_id: 'w9', tab_id: 'w9:t1',
                                          agent_session: { source: 'herdr:pi', kind: 'path', value: '/tmp/test-session' } } })
RUBY

Given('Herdr starts the agent only in the linked worktree') do
  install_fake_herdr(<<~RUBY)
    require 'json'
    case ARGV[0, 2]
    when ['workspace', 'create']
      cwd = ARGV[ARGV.index('--cwd') + 1]
      #{WORKTREE_PI_TRUST_CHECK}
      File.write(File.expand_path('workspace-cwd', __dir__), cwd)
      puts #{CANNED_CREATE_RESPONSE.dump}
    when ['pane', 'get']
      if File.exist?(File.expand_path('pane-closed', __dir__))
        if File.exist?(File.expand_path('ambiguous-close', __dir__))
          puts JSON.generate(result: { pane: { pane_id: 'w9:p1' } })
        else
          puts #{PANE_NOT_FOUND_RESPONSE.dump}
          exit 1
        end
      end
      cwd = File.read(File.expand_path('workspace-cwd', __dir__))
      cwd = '/' if File.exist?(File.expand_path('wrong-pane-cwd', __dir__))
      puts JSON.generate(result: { pane: { pane_id: 'w9:p1', foreground_cwd: cwd } })
    when ['pane', 'close'] then File.write(File.expand_path('pane-closed', __dir__), '')
    when ['agent', 'start']
      #{WORKTREE_AGENT_START}
    #{WORKTREE_TASK_LAUNCH}
    else abort "unexpected command: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('the Herdr client status read fails') do
  File.write(File.join(@herdr_directory, 'status-fails'), '')
end

Given('the new agent start fails in the linked worktree') do
  File.write(File.join(@herdr_directory, 'agent-start-fails'), '')
end

Given('the new pane stays outside the linked worktree') do
  File.write(File.join(@herdr_directory, 'wrong-pane-cwd'), '')
end

Given('the worker worktree destination already exists') do
  Dir.mkdir(@worktree)
  File.write(File.join(@worktree, 'untouched'), 'keep')
end

Given('the start directory is outside the Git project') do
  @working_directory = new_temporary_directory
end

Then('the worker has a separate linked worktree at the project\'s HEAD') do
  output, status = Open3.capture2('git', '-C', @worktree, 'rev-parse', '--show-toplevel', 'HEAD')
  expected, = Open3.capture2('git', '-C', @project, 'rev-parse', 'HEAD')
  assert_equal [true, true, @worktree, expected.strip], [@status.success?, status.success?, *output.lines.map(&:strip)]
end

def run_worker_cli(*, environment: @environment)
  worker = File.join(@worktree, 'bin', 'riddim')
  Bundler.with_unbundled_env { Open3.capture3(environment, worker, *, chdir: @worktree) }
end

Then('Riddim inside the worktree can start another agent using the original profile and state') do
  environment = @environment.merge('RIDDIM_CONFIG_DIR' => nil, 'RIDDIM_STATE_DIR' => nil)
  stdout, stderr, status = run_worker_cli('start', 'another', environment: environment)
  assert_equal [true, true, true, false], [status.success?, stdout.include?('started another'),
                                           File.file?(scenario_record_path('another')),
                                           File.exist?(File.join(@worktree, 'state', 'another.meta'))], stderr
end

When("I replace the worker's runtime marker with a symlink") do
  git_dir, status = Open3.capture2('git', '-C', @worktree, 'rev-parse', '--absolute-git-dir')
  raise 'missing linked Git admin directory' unless status.success?

  marker = File.join(git_dir.strip, 'riddim-home')
  File.delete(marker)
  File.symlink(@project, marker)
end

Then('Riddim in the worktree refuses the marker') do
  environment = @environment.merge('RIDDIM_CONFIG_DIR' => nil, 'RIDDIM_STATE_DIR' => nil)
  _stdout, stderr, status = run_worker_cli('list', environment: environment)
  assert_equal [1, true], [status.exitstatus, stderr.include?('worktree marker cannot be read')]
end

Then('Riddim in the worktree respects an explicit state override') do
  other_state = File.join(new_temporary_directory, 'state')
  environment = @environment.merge('RIDDIM_CONFIG_DIR' => nil, 'RIDDIM_STATE_DIR' => other_state)
  stdout, stderr, status = run_worker_cli('list', '--json', environment: environment)
  assert_equal [true, 0], [status.success?, JSON.parse(stdout).fetch('records').size], stderr
end

Then('no Herdr workspace is created for the changed worker branch') do
  assert_equal [false, true, true], [@status.success?, herdr_invocations.none? do |line|
    line.include?('workspace create')
  end,
                                     File.directory?(@worktree)]
end

Then('the start output names the new worktree and branch') do
  assert_equal "started worker in w9:p1\nworktree #{@worktree} (branch riddim/worker)\n", @stdout
end

Then('Herdr creates a workspace in the new worktree without focus') do
  assert_includes herdr_invocations,
                  "--session default workspace create --cwd #{@worktree} --label riddim-worker --no-focus", @stderr
end

Then('the worker record binds the new worktree and its exact Herdr pane') do
  fields = File.readlines(scenario_record_path('worker')).to_h { |line| line.strip.split('=', 2) }
  assert_equal({ 'project' => @project, 'worktree' => @worktree, 'branch' => 'riddim/worker',
                 'herdr_pane_id' => 'w9:p1' }, fields.slice('project', 'worktree', 'branch', 'herdr_pane_id'))
end

Then('no worker worktree is created') do
  refute File.exist?(@worktree)
end

Then('the existing worker destination is untouched') do
  assert_equal 'keep', File.read(File.join(@worktree, 'untouched'))
end

Then('the failed start leaves the linked worktree intact') do
  assert File.directory?(@worktree)
end

Then('the misplaced pane is closed without deleting the worktree') do
  assert_equal [true, false, true, true],
               [herdr_invocations.any? { |invocation| invocation.include?('pane close w9:p1') },
                herdr_invocations.any? { |invocation| invocation.include?('agent start worker') },
                File.directory?(@worktree), File.exist?(File.join(@herdr_directory, 'pane-closed'))]
end

Then('only the exact worktree has a new trust decision') do
  trust = JSON.parse(File.read(@pi_trust_file))
  parent = File.dirname(@worktree)
  expected = { parent => false, '/unrelated-project' => true, @worktree => true }
  assert_equal [true, expected, true, true],
               [@status.success?, trust, trust.keys.sort == expected.keys.sort,
                File.stat(@pi_trust_file).mode & 0o777 == 0o600], @stderr
end

Then('the new Pi trust store contains only the worktree trust') do
  trust = JSON.parse(File.read(@pi_trust_file))
  assert_equal [true, { @worktree => true }, true, true],
               [@status.success?, trust, File.stat(@pi_agent_directory).mode & 0o777 == 0o700,
                File.stat(@pi_trust_file).mode & 0o777 == 0o600], @stderr
end

Then('the Pi trust store remains unchanged') do
  trust = JSON.parse(File.read(@pi_trust_file))
  expected = { File.dirname(@worktree) => false, '/unrelated-project' => true }
  assert_equal [true, expected], [@status.success?, trust], @stderr
end

Then('the Pi trust store directory remains absent') do
  assert_equal [true, false, false],
               [@status.success?, File.exist?(@pi_agent_directory), File.symlink?(@pi_agent_directory)], @stderr
end
