# frozen_string_literal: true

Given('the worker has reviewable dirty files') do
  %w[staged.txt deleted.txt staged-deleted.txt rename-source.txt].each do |path|
    File.write(File.join(@worktree, path), 'committed')
  end
  dirty_git!('add', '.')
  dirty_git!('commit', '-m', 'dirty fixture base')
  @worker_tip = dirty_git!('rev-parse', 'HEAD').strip
  File.write(File.join(@worktree, 'staged.txt'), 'staged version')
  dirty_git!('add', 'staged.txt')
  File.write(File.join(@worktree, 'staged.txt'), 'unstaged version')
  File.write(File.join(@worktree, 'tracked.txt'), 'reviewed edit')
  File.unlink(File.join(@worktree, 'deleted.txt'))
  File.write(File.join(@worktree, 'new file.txt'), 'reviewed untracked')
  File.write(File.join(@worktree, 'staged-new.txt'), 'staged new file')
  dirty_git!('add', 'staged-new.txt')
  dirty_git!('rm', 'staged-deleted.txt')
  dirty_git!('mv', 'rename-source.txt', 'renamed.txt')
  @dirty_index_path = dirty_git!('rev-parse', '--git-path', 'index').strip
  @dirty_index = File.binread(@dirty_index_path)
end

Given('the reviewed dirty files change in {string}') do |kind|
  case kind
  when 'tracked content' then File.write(File.join(@worktree, 'tracked.txt'), 'later edit')
  when 'new file' then File.write(File.join(@worktree, 'later.txt'), 'new')
  when 'deleted file' then File.unlink(File.join(@worktree, 'tracked.txt'))
  when 'staged content' then dirty_git!('add', 'staged.txt')
  when 'staged state' then dirty_git!('restore', '--staged', 'staged.txt')
  when 'untracked content' then File.write(File.join(@worktree, 'new file.txt'), 'later untracked')
  when 'executable mode' then File.chmod(0o755, File.join(@worktree, 'new file.txt'))
  when 'same stat content'
    path = File.join(@worktree, 'tracked.txt')
    stat = File.stat(path)
    File.write(path, 'replaced edit')
    File.utime(stat.atime, stat.mtime, path)
  else raise "unknown dirty change #{kind}"
  end
end

Given('the worker has unsupported {string} content') do |kind|
  case kind
  when 'ignored', 'hidden' then step "the worker gains \"#{kind}\" data"
  when 'sensitive' then File.write(File.join(@worktree, '.env'), 'PRIVATE=do-not-print')
  when 'nested repo' then dirty_git!('init', File.join(@worktree, 'nested'))
  when 'bare repo' then dirty_git!('init', '--bare', File.join(@worktree, 'nested.git'))
  when 'symlink' then File.symlink(@project, File.join(@worktree, 'outside'))
  when 'hardlink' then File.link(File.join(@project, 'tracked.txt'), File.join(@worktree, 'outside'))
  when 'control filename' then File.write(File.join(@worktree, "bad\nname"), 'not printable')
  when 'skip-worktree' then dirty_git!('update-index', '--skip-worktree', 'tracked.txt')
  when 'submodule' then dirty_git!('update-index', '--add', '--cacheinfo', "160000,#{@worker_tip},sub")
  when 'index lock' then File.write(dirty_git!('rev-parse', '--git-path', 'index.lock').strip, 'busy')
  when 'intent-to-add'
    File.write(File.join(@worktree, 'intent.txt'), 'not staged')
    dirty_git!('add', '-N', 'intent.txt')
  when 'conflicted'
    blob = dirty_git!('rev-parse', 'HEAD:tracked.txt').strip
    input = "100644 #{blob} 1\ttracked.txt\n100644 #{blob} 2\ttracked.txt\n"
    dirty_git!('update-index', '--index-info', stdin_data: input)
  else raise "unknown unsupported content #{kind}"
  end
end

Then('discard inspection inventories the exact dirty files without mutation') do
  files = @discard_scope.fetch('files').to_h { |file| [file.fetch('path'), file] }
  output, error, status = run_riddim('discard', 'worker', '--inspect')
  assert_equal [' M', 'MM', ' D', '??', 'A ', 'D ', 'A ', 'D ', 64, true, 'unstaged version', false, true, true, true],
               [files.fetch('tracked.txt').fetch('status'), files.fetch('staged.txt').fetch('status'),
                files.fetch('deleted.txt').fetch('status'), files.fetch('new file.txt').fetch('status'),
                files.fetch('staged-new.txt').fetch('status'), files.fetch('staged-deleted.txt').fetch('status'),
                files.fetch('renamed.txt').fetch('status'), files.fetch('rename-source.txt').fetch('status'),
                @discard_scope.fetch('snapshot').length, @discard_scope.fetch('loss').include?('irreversible'),
                File.read(File.join(@worktree, 'staged.txt')),
                herdr_invocations.any? { |line| line.include?('pane close') }, status.success?,
                JSON.parse(output) == @discard_scope, File.binread(@dirty_index_path) == @dirty_index], error
end

Then('incomplete dirty discard records file loss before removal failure') do
  events = discard_audit_events.map { |event| event.fetch('event') }
  assert_equal [false, true, true, true, true, false, "worker change\n"],
               [@status.success?, File.file?(scenario_record_path('worker')), File.directory?(@worktree),
                events.include?('authorized-attempt'), events.include?('files-discarded'), events.include?('complete'),
                File.read(File.join(@worktree, 'tracked.txt'))], @stderr
end

def dirty_git!(*, **)
  output, status = Open3.capture2e('git', '-C', @worktree, *, **)
  raise output unless status.success?

  output
end
