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
  step 'Riddim is invoked from its linked runtime'
end

Given('Riddim is invoked from its linked runtime') do
  @runtime_common = central_git!(@runtime, 'rev-parse', '--path-format=absolute', '--git-common-dir')
  linked = File.join(new_temporary_directory, 'linked-runtime')
  central_git!(@runtime, 'worktree', 'add', '-qb', 'runtime-worker', linked)
  @riddim_cli = File.join(linked, 'bin', 'riddim')
  @runtime_worktrees = central_git!(@runtime, 'worktree', 'list', '--porcelain')
  @target_head = central_git!(@project, 'rev-parse', 'HEAD')
  @target_worktrees = central_git!(@project, 'worktree', 'list', '--porcelain')
end

Given('Riddim runs from a {string} primary installation') do |layout|
  if layout == 'separate-git-dir'
    admin = File.join(new_temporary_directory, 'runtime.git')
    central_git!(@runtime, 'init', '-q', '--separate-git-dir', admin)
  else
    central_git!(@runtime, 'init', '-q')
  end
  central_git!(@runtime, 'add', '.')
  central_git!(@runtime, 'commit', '-qm', 'runtime')
  prepare_submodule_runtime if layout == 'submodule'
  @riddim_cli = File.join(@runtime, 'bin', 'riddim')
  @worktree = central_worker_path(@project)
end

def prepare_submodule_runtime
  superproject = File.join(new_temporary_directory, 'superproject')
  Dir.mkdir(superproject)
  central_git!(superproject, 'init', '-q')
  central_git!(superproject, '-c', 'protocol.file.allow=always', 'submodule', 'add', '-q', @runtime, 'riddim')
  central_git!(superproject, 'commit', '-qm', 'runtime submodule')
  @runtime = File.join(superproject, 'riddim')
end

Then('the ambiguous runtime is refused without worker assets in Git metadata') do
  wrong_root = File.join(File.dirname(@runtime_common), '.riddim-worktrees')
  assert_equal [1, true, false, false, false, true],
               [@status.exitstatus, @stderr.include?('cannot locate verified primary checkout'),
                File.exist?(@worktree), File.exist?(wrong_root), File.exist?(scenario_record_path('worker')),
                herdr_invocations.none? { |line| line.include?('workspace create') }], @stderr
  assert_equal [@runtime_worktrees, @target_head, @target_worktrees],
               [central_git!(@runtime, 'worktree', 'list', '--porcelain'),
                central_git!(@project, 'rev-parse', 'HEAD'),
                central_git!(@project, 'worktree', 'list', '--porcelain')]
  assert_equal ['.meta-worker.lock'], Dir.children(scenario_state_dir).sort
end

Given('the target is accessed through a linked checkout') do
  linked = File.join(new_temporary_directory, 'different-target-name')
  central_git!(@project, 'worktree', 'add', '-qb', 'target-source', linked)
  @working_directory = linked
end

Given('the target is a linked checkout with {string} metadata') do |layout|
  parent = new_temporary_directory
  @target_common = File.join(parent, 'target.git')
  if layout == 'separate-git-dir'
    central_git!(@project, 'init', '-q', '--separate-git-dir', @target_common)
  else
    central_git!(parent, 'clone', '--bare', '-q', @project, @target_common)
  end
  @working_directory = File.join(new_temporary_directory, 'linked-target')
  source = layout == 'bare' ? @target_common : @project
  central_git!(source, 'worktree', 'add', '-qb', 'target-source', @working_directory)
  @target_head = central_git!(@working_directory, 'rev-parse', 'HEAD')
  @target_worktrees = central_git!(@target_common, 'worktree', 'list', '--porcelain')
end

Then('the ambiguous linked target is refused before creating any worker assets') do
  storage = File.join(File.dirname(@runtime), '.riddim-worktrees')
  branch_exists = Open3.capture3('git', '-C', @target_common, 'show-ref', '--verify', '--quiet',
                                 'refs/heads/riddim/worker').last.success?
  assert_equal [1, true, false, false, true, false, @target_head, @target_worktrees],
               [@status.exitstatus, @stderr.include?('unsupported linked Git layout'),
                File.exist?(storage), File.exist?(scenario_record_path('worker')),
                herdr_invocations.none? { |line| line.include?('workspace create') }, branch_exists,
                central_git!(@working_directory, 'rev-parse', 'HEAD'),
                central_git!(@target_common, 'worktree', 'list', '--porcelain')], @stderr
  assert_equal ['.meta-worker.lock'], Dir.children(scenario_state_dir).sort
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
