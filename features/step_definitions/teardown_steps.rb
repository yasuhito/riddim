# frozen_string_literal: true

Given('the caller has the same pane ID in another session') do
  @environment.merge!('HERDR_ENV' => '1', 'HERDR_SESSION' => 'other-session', 'HERDR_PANE_ID' => 'w9:p1')
end

Given('the caller and cwd scan are outside the project') do
  @working_directory = new_temporary_directory
  File.write(File.join(@herdr_directory, 'omit-project'), '')
end

Given('the caller is the recorded worker pane with the default session implicit') do
  @environment.merge!('HERDR_ENV' => '1', 'HERDR_SESSION' => nil, 'HERDR_PANE_ID' => 'w9:p1')
end

Given('the caller is the recorded worker pane') do
  @environment.merge!('HERDR_ENV' => '1', 'HERDR_SESSION' => 'default', 'HERDR_PANE_ID' => 'w9:p1')
end

Given('the task input is removed after launch') do
  File.delete(File.join(@project, 'task.md'))
end

When('a fresh fake pane and task input are prepared') do
  %w[pane-closed agent-named launch-submitted].each do |marker|
    path = File.join(@herdr_directory, marker)
    FileUtils.rm_f(path)
  end
  File.write(File.join(@project, 'task.md'), 'A replacement task for this name.')
end

Given('the worker branch is fast-forward merged into local main') do
  output, status = Open3.capture2e('git', '-C', @project, 'merge', '--ff-only', 'riddim/worker')
  raise "cannot land worker: #{output}" unless status.success?
end

Given('a fake cwd scan reports no worker process') do
  install_fake_cwd_scan
end

Given('a fake cwd scan reports a worker process') do
  install_fake_cwd_scan
  File.write(File.join(@herdr_directory, 'cwd-holder'), '')
end

Given('Pi already exited the recorded pane') do
  File.write(File.join(@herdr_directory, 'agent-gone'), '')
end

Given('the recorded pane is already gone') do
  File.write(File.join(@herdr_directory, 'pane-closed'), '')
end

Given('the pane read after close is ambiguous') do
  File.write(File.join(@herdr_directory, 'ambiguous-close'), '')
end

Given('the generation archive already exists') do
  File.write(File.join(scenario_state_dir, "worker.#{@generation}.brief"), 'existing evidence')
end

Given('a different agent occupies the worker pane') do
  File.write(File.join(@herdr_directory, 'unrecognized-pi'), '')
end

Given('Git refuses to remove the worker worktree') do
  git = ENV.fetch('PATH').split(File::PATH_SEPARATOR).map { |part| File.join(part, 'git') }
           .find { |path| File.file?(path) && File.executable?(path) }
  raise 'Git executable is required' unless git

  executable = File.join(@herdr_directory, 'git')
  File.write(executable, <<~RUBY)
    #!/usr/bin/ruby
    if ARGV.include?('worktree') && ARGV.include?('remove')
      warn 'simulated Git worktree removal failure'
      exit 8
    end
    exec #{git.dump}, *ARGV
  RUBY
  File.chmod(0o755, executable)
end

Given('the cwd scan returns a malformed record') do
  File.write(File.join(@herdr_directory, 'malformed-scan'), '')
end

Given('the cwd scan cannot finish') do
  File.write(File.join(@herdr_directory, 'cwd-scan-fails'), '')
end

Given('the cwd scan observes a new decision report') do
  File.write(File.join(@herdr_directory, 'new-decision'), '')
end

Given('a competing writer attempts to replace the owner during the cwd scan') do
  File.write(File.join(@herdr_directory, 'try-rebind'), '')
end

FAKE_CWD_SCAN = <<~'RUBY'
  #!/usr/bin/ruby
  abort 'unexpected cwd scan arguments' unless ARGV == %w[-a -d cwd -Fpn]
  directory = File.expand_path(__dir__)
  if File.exist?(File.join(directory, 'cwd-scan-fails'))
    warn 'cwd scan failed'
    exit 2
  end
  project = File.exist?(File.join(directory, 'omit-project')) ? '/tmp' : ENV.fetch('RIDDIM_TEST_PROJECT')
  puts "p#{Process.ppid}\nfcwd\nn#{project}"
  puts "p42\nfcwd\nn#{ENV.fetch('RIDDIM_TEST_WORKTREE')}" if File.exist?(File.join(directory, 'cwd-holder'))
  puts 'not-an-lsof-field' if File.exist?(File.join(directory, 'malformed-scan'))
  if File.exist?(File.join(directory, 'new-decision'))
    File.open(ENV.fetch('RIDDIM_TEST_STATUS'), 'a') { |file| file.puts('needs-decision [at=124]: new gate') }
  end
  if File.exist?(File.join(directory, 'try-rebind'))
    state = ENV.fetch('RIDDIM_STATE_DIR')
    File.open(File.join(state, '.meta-worker.lock'), File::RDWR | File::NOFOLLOW) do |file|
      if file.flock(File::LOCK_EX | File::LOCK_NB)
        record = File.join(state, 'worker.meta')
        bytes = File.read(record).sub(/^spawn_gen=.+$/, 'spawn_gen=s9999.9999.9999')
        replacement = "#{record}.replacement"
        File.write(replacement, bytes)
        File.rename(replacement, record)
      else
        File.write(File.join(directory, 'writer-blocked'), '')
      end
    end
  end
RUBY

def install_fake_cwd_scan
  executable = File.join(@herdr_directory, 'lsof')
  File.write(executable, FAKE_CWD_SCAN)
  File.chmod(0o755, executable)
  @environment['RIDDIM_TEST_PROJECT'] = @project
  @environment['RIDDIM_TEST_WORKTREE'] = @worktree
  @environment['RIDDIM_TEST_STATUS'] = @result_path
  @generation = File.read(scenario_record_path('worker'))[/^spawn_gen=(.+)$/, 1]
  @trace = File.join(scenario_state_dir, "worker.brief.trace.#{@generation}.jsonl")
  File.write(@trace, "{\"event\":\"request_prepared\"}\n")
end

Then('the archived brief survives beside a new worker generation') do
  archived = File.join(scenario_state_dir, "worker.#{@generation}.brief")
  record = File.read(scenario_record_path('worker'))
  assert_equal [true, true, true, true, true],
               [@status.success?, File.read(archived).include?('Commit one change'),
                record[/^spawn_gen=(.+)$/, 1] != @generation,
                File.read(File.join(scenario_state_dir, 'worker.brief')).include?('A replacement task'),
                File.directory?(@worktree)], @stderr
end

Then('teardown refuses an unsupported force flag without touching Herdr') do
  assert_equal [2, '', true, []], [@status.exitstatus, @stdout,
                                   @stderr.include?('Usage: riddim teardown'), herdr_invocations]
end

Then('teardown confirms the pane gone, retires the linked worktree and branch, and archives the brief') do
  archived = File.join(scenario_state_dir, "worker.#{@generation}.brief")
  branch = Open3.capture3('git', '-C', @project, 'show-ref', '--verify', 'refs/heads/riddim/worker').last
  assert_equal [true, false, false, false, false, true, true, true, true],
               [@status.success?, File.exist?(scenario_record_path('worker')), File.exist?(@worktree),
                branch.success?, File.exist?(File.join(scenario_state_dir, 'worker.brief')),
                File.file?(archived) && File.read(archived).include?('Commit one change'),
                File.file?(@result_path), File.file?(@trace),
                herdr_invocations.any? { |line| line.include?('pane close w9:p1') }], @stderr
end

Then('teardown blocks the competing owner until the original assets are retired') do
  assert_equal [true, true, false, false],
               [@status.success?, File.file?(File.join(@herdr_directory, 'writer-blocked')),
                File.exist?(scenario_record_path('worker')), File.exist?(@worktree)], @stderr
end

Then('teardown retires the linked worktree without closing the pane again') do
  assert_equal [true, false, false],
               [@status.success?, File.exist?(@worktree),
                herdr_invocations.any? { |line| line.include?('pane close w9:p1') }], @stderr
end

Then('teardown refuses before closing the pane and keeps all worker assets') do
  assert_equal [false, true, true, true, false],
               [@status.success?, File.file?(scenario_record_path('worker')), File.directory?(@worktree),
                File.file?(File.join(scenario_state_dir, 'worker.brief')),
                herdr_invocations.any? { |line| line.include?('pane close w9:p1') }], @stderr
end

Then('teardown refuses and keeps the linked worktree, branch, and ownership record') do
  branch = Open3.capture3('git', '-C', @project, 'show-ref', '--verify', 'refs/heads/riddim/worker').last
  assert_equal [false, true, true, true, true],
               [@status.success?, File.file?(scenario_record_path('worker')), File.directory?(@worktree),
                branch.success?, File.file?(File.join(scenario_state_dir, 'worker.brief'))], @stderr
end
