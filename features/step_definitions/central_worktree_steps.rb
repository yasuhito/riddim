# frozen_string_literal: true

require 'digest'

def central_worker_path(project)
  common, status = Open3.capture2('git', '-C', project, 'rev-parse', '--path-format=absolute', '--git-common-dir')
  raise 'missing Git common directory' unless status.success?

  id = Digest::SHA256.hexdigest(File.realpath(common.strip))
  File.join(File.dirname(@runtime), '.riddim-worktrees', "#{File.basename(project)}-#{id}", 'worker')
end

def central_git!(directory, *)
  out, err, status = Open3.capture3('git', '-C', directory, '-c', 'user.name=Test',
                                    '-c', 'user.email=test@example.invalid', *)
  raise "Git fixture failed: #{out}#{err}" unless status.success?

  out.strip
end

Given('Riddim runs from a linked runtime checkout') do
  central_git!(@runtime, 'init', '-q')
  central_git!(@runtime, 'add', '.')
  central_git!(@runtime, 'commit', '-qm', 'runtime')
  linked = File.join(new_temporary_directory, 'linked-runtime')
  central_git!(@runtime, 'worktree', 'add', '-qb', 'runtime-worker', linked)
  @riddim_cli = File.join(linked, 'bin', 'riddim')
end

Given('the target is accessed through a linked checkout') do
  linked = File.join(new_temporary_directory, 'different-target-name')
  central_git!(@project, 'worktree', 'add', '-qb', 'target-source', linked)
  @working_directory = linked
end

Given('the central storage has an unsafe {string}') do |kind|
  @untouched = new_temporary_directory
  File.write(File.join(@untouched, 'keep'), 'unchanged')
  root = File.join(File.dirname(@runtime), '.riddim-worktrees')
  repository = File.dirname(@worktree)
  path = kind.start_with?('repository') ? repository : root
  FileUtils.mkdir_p(root) if kind.start_with?('repository')
  case kind
  when 'root symlink', 'repository symlink' then File.symlink(@untouched, path)
  when 'root file', 'repository file' then File.write(path, 'unchanged')
  when 'writable root'
    Dir.mkdir(root)
    File.chmod(0o777, root)
  when 'destination symlink'
    FileUtils.mkdir_p(repository)
    File.symlink(@untouched, @worktree)
  end
end

Then('unsafe central storage is refused without changing its contents') do
  assert_equal [false, true, ['keep'], 'unchanged'],
               [@status.success?, herdr_invocations.none? { |line| line.include?('workspace create') },
                Dir.children(@untouched), File.read(File.join(@untouched, 'keep'))], @stderr
end

Given('the worker branch already exists without a worktree') do
  central_git!(@project, 'branch', 'riddim/worker')
  @original_tip = central_git!(@project, 'rev-parse', 'riddim/worker')
end

Then('the failed allocation leaves no central directories or changed branch') do
  assert_equal [false, false, @original_tip],
               [@status.success?, File.exist?(File.join(File.dirname(@runtime), '.riddim-worktrees')),
                central_git!(@project, 'rev-parse', 'riddim/worker')], @stderr
end

Given('another independent project with the same basename has a worker') do
  @other_project = File.join(new_temporary_directory, 'project')
  Dir.mkdir(@other_project)
  central_git!(@other_project, 'init', '-q')
  central_git!(@other_project, 'commit', '--allow-empty', '-qm', 'other base')
  original = @working_directory
  original_state = @environment.fetch('RIDDIM_STATE_DIR')
  @environment['RIDDIM_STATE_DIR'] = File.join(new_temporary_directory, 'state')
  @working_directory = @other_project
  out, err, status = run_riddim('start', 'worker', '--worktree')
  raise "other start failed: #{out}#{err}" unless status.success?

  @other_worktree = central_worker_path(@other_project)
  @environment['RIDDIM_STATE_DIR'] = original_state
  @working_directory = original
end

Then('both repositories have separate central workers') do
  assert_equal [true, true, true, true],
               [@status.success?, @worktree != @other_worktree, File.directory?(@worktree),
                File.directory?(@other_worktree)], @stderr
end

Given('a legacy sibling local-only task was started') do
  step 'a local-only task was started'
  legacy = File.join(File.dirname(@project), 'project-riddim-worker')
  central_git!(@project, 'worktree', 'move', @worktree, legacy)
  record = scenario_record_path('worker')
  File.write(record, File.read(record).sub("worktree=#{@worktree}\n", "worktree=#{legacy}\n"))
  admin = central_git!(legacy, 'rev-parse', '--absolute-git-dir')
  marker = File.join(admin, 'riddim-home')
  File.write(marker, File.read(marker).sub("worktree=#{@worktree}\n", "worktree=#{legacy}\n"))
  @worktree = legacy
end

Given('another worker has files in the same central repository directory') do
  @neighbor = File.join(File.dirname(@worktree), 'neighbor', 'unfinished.txt')
  FileUtils.mkdir_p(File.dirname(@neighbor))
  File.write(@neighbor, 'uncommitted work')
end

Then('central teardown preserves the other worker and storage parents') do
  step 'teardown confirms the pane gone, retires the linked worktree and branch, and archives the brief'
  assert_equal ['uncommitted work', true], [File.read(@neighbor), File.directory?(File.dirname(@worktree))]
end

Then('the primary runtime remains clean with central workers outside it') do
  fields = File.readlines(scenario_record_path('worker')).to_h { |line| line.strip.split('=', 2) }
  assert_equal [true, '', @worktree, false],
               [@status.success?, central_git!(@runtime, 'status', '--porcelain', '--untracked-files=all'),
                fields['worktree'], @worktree.start_with?("#{@runtime}/")], @stderr
end

Then('the worker lives in the central runtime without changing the target parent') do
  fields = File.readlines(scenario_record_path('worker')).to_h { |line| line.strip.split('=', 2) }
  assert_equal [true, @worktree, ['project']],
               [@status.success?, fields['worktree'], Dir.children(File.dirname(@project)).sort], @stderr
end
