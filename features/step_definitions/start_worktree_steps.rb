# frozen_string_literal: true

require 'open3'

Given('a local Git project for worktree start') do
  @project = File.join(new_temporary_directory, 'project')
  Dir.mkdir(@project)
  git = ->(*args) { Open3.capture3('git', '-C', @project, *args) }
  raise 'git init failed' unless git.call('init', '-q').last.success?

  File.write(File.join(@project, 'tracked.txt'), "base\n")
  raise 'git add failed' unless git.call('add', 'tracked.txt').last.success?
  raise 'git commit failed' unless git.call('-c', 'user.name=Riddim', '-c', 'user.email=test@example.invalid',
                                            'commit', '-qm', 'base').last.success?

  @worktree = File.join(File.dirname(@project), 'project-riddim-worker')
  @working_directory = @project
end

Given('Herdr starts the agent only in the linked worktree') do
  install_fake_herdr(<<~RUBY)
    require 'json'
    case ARGV[0, 2]
    when ['workspace', 'create']
      cwd = ARGV[ARGV.index('--cwd') + 1]
      File.write(File.expand_path('workspace-cwd', __dir__), cwd)
      puts #{CANNED_CREATE_RESPONSE.dump}
    when ['pane', 'get']
      if File.exist?(File.expand_path('pane-closed', __dir__))
        puts #{PANE_NOT_FOUND_RESPONSE.dump}
        exit 1
      end
      cwd = File.read(File.expand_path('workspace-cwd', __dir__))
      cwd = '/' if File.exist?(File.expand_path('wrong-pane-cwd', __dir__))
      puts JSON.generate(result: { pane: { pane_id: 'w9:p1', foreground_cwd: cwd } })
    when ['pane', 'close'] then File.write(File.expand_path('pane-closed', __dir__), '')
    when ['agent', 'start']
      if File.exist?(File.expand_path('agent-start-fails', __dir__))
        warn 'agent refused start'
        exit 7
      end
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
