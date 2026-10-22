# frozen_string_literal: true

When('I inspect the worker discard scope') do
  @stdout, @stderr, @status = run_riddim('discard', 'worker', '--inspect')
  raise "discard inspection failed: #{@stderr}" unless @status.success?

  @discard_scope = JSON.parse(@stdout)
  @discard_main = Open3.capture2('git', '-C', @project, 'rev-parse', 'main').first.strip
  @discard_unrelated = File.join(@project, 'unrelated-local-data')
  File.write(@discard_unrelated, 'keep me')
  Open3.capture2e('git', '-C', @project, 'branch', 'unrelated-branch')
end

Given('the discard approval field {string} is stale') do |field|
  @discard_scope[field] = 'stale'
end

When('I invoke the confirmed discard') do
  @stdout, @stderr, @status = run_riddim(*discard_arguments, '--confirm-discard')
end

When('I invoke discard without the confirmation flag') do
  @stdout, @stderr, @status = run_riddim(*discard_arguments)
end

def discard_arguments
  ['discard', 'worker', '--generation', @discard_scope.fetch('generation'),
   '--head', @discard_scope.fetch('head'), '--snapshot', @discard_scope.fetch('snapshot')]
end

Given('the worker commits another change after review') do
  step 'the worker commits another change in its own branch'
end

Given('the discard caller is a marked worker') do
  @environment['RIDDIM_ACTOR'] = 'branch'
end

Given('the worker gains {string} data') do |kind|
  @discard_data = File.join(@worktree, %w[tracked hidden].include?(kind) ? 'tracked.txt' : 'new-data')
  if kind == 'ignored'
    info = Open3.capture2('git', '-C', @worktree, 'rev-parse', '--git-path', 'info/exclude').first.strip
    File.open(info, 'a') { |file| file.puts('new-data') }
  elsif kind == 'hidden'
    Open3.capture2e('git', '-C', @worktree, 'update-index', '--assume-unchanged', 'tracked.txt')
  end
  File.write(@discard_data, 'new valuable data')
end

Given('the cwd scan creates untracked worker data') do
  executable = File.join(@herdr_directory, 'lsof')
  File.open(executable, 'a') do |file|
    file.puts("File.write(File.join(ENV.fetch('RIDDIM_TEST_WORKTREE'), 'new-data'), 'new valuable data')")
  end
  @discard_data = File.join(@worktree, 'new-data')
end

Given('Git refuses discard branch deletion') do
  git = Open3.capture2('which', 'git').first.strip
  executable = File.join(@herdr_directory, 'git')
  File.write(executable, <<~RUBY)
    #!/usr/bin/ruby
    abort 'simulated branch deletion failure' if ARGV.include?('update-ref')
    exec #{git.dump}, *ARGV
  RUBY
  File.chmod(0o755, executable)
end

Given('Git moves the worker branch during discard deletion') do
  git = Open3.capture2('which', 'git').first.strip
  executable = File.join(@herdr_directory, 'git')
  File.write(executable, <<~RUBY)
    #!/usr/bin/ruby
    if ARGV.include?('update-ref') && ARGV.include?('-d')
      system #{git.dump}, '-C', #{@project.dump}, 'update-ref', 'refs/heads/riddim/worker', #{@discard_main.dump}
    end
    exec #{git.dump}, *ARGV
  RUBY
  File.chmod(0o755, executable)
end

Then('incomplete discard retains the changed branch and record') do
  tip = Open3.capture2('git', '-C', @project, 'rev-parse', 'refs/heads/riddim/worker').first.strip
  assert_equal [false, true, false, @discard_main, true],
               [@status.success?, File.file?(scenario_record_path('worker')), File.exist?(@worktree), tip,
                @stderr.include?('some assets may already be removed')], @stderr
end

Then('discard inspection names the exact clean scope without mutation') do
  assert_equal [@generation, @worker_tip, @worktree, 'clean-only', true, false],
               [@discard_scope['generation'], @discard_scope['head'], @discard_scope['worktree'],
                @discard_scope['files'], File.file?(scenario_record_path('worker')),
                herdr_invocations.any? { |line| line.include?('pane close') }]
end

Then('authorized discard removes only the worker assets and keeps audit evidence') do
  audit = discard_audit_events
  archived = File.join(scenario_state_dir, "worker.#{@generation}.brief")
  main = Open3.capture2('git', '-C', @project, 'rev-parse', 'main').first.strip
  unrelated = Open3.capture2e('git', '-C', @project, 'show-ref', '--verify', 'refs/heads/unrelated-branch').last
  branch = Open3.capture2e('git', '-C', @project, 'show-ref', '--verify', 'refs/heads/riddim/worker').last
  assert_equal [true, false, false, false, true, true, true, true, true, true, 'complete'],
               [@status.success?, File.exist?(@worktree), File.exist?(scenario_record_path('worker')), branch.success?,
                main == @discard_main, unrelated.success?, File.read(@discard_unrelated) == 'keep me',
                File.file?(archived), File.file?(@result_path), File.file?(@trace), audit.last&.fetch('event')], @stderr
end

Then('discard retains the new local data and worker assets') do
  assert_equal [false, true, true, 'new valuable data'],
               [@status.success?, File.file?(scenario_record_path('worker')), File.directory?(@worktree),
                File.read(@discard_data)], @stderr
end

Then('incomplete discard keeps the record, Git assets and attempt evidence') do
  events = discard_audit_events.map { |event| event.fetch('event') }
  assert_equal [false, true, true, true, false],
               [@status.success?, File.file?(scenario_record_path('worker')), File.directory?(@worktree),
                events.include?('authorized-attempt'), events.include?('complete')], @stderr
end

Then('incomplete discard keeps the branch and record after worktree removal') do
  branch = Open3.capture2e('git', '-C', @project, 'show-ref', '--verify', 'refs/heads/riddim/worker').last
  assert_equal [false, true, false, true, 'worktree-removed'],
               [@status.success?, File.file?(scenario_record_path('worker')), File.exist?(@worktree),
                branch.success?, discard_audit_events.last&.fetch('event')], @stderr
end

def discard_audit_events
  files = Dir[File.join(scenario_state_dir, "worker.#{@generation}.discard.*.jsonl")]
  files.flat_map { |path| File.readlines(path).map { |line| JSON.parse(line) } }
end
