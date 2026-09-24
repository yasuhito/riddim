# frozen_string_literal: true

require 'open3'

Given('the operator approves the reviewed worker branch tip') do
  @approved_head = worker_branch_tip
end

Given('the caller is the marked task worker') do
  @environment.merge!('RIDDIM_ACTOR' => 'branch')
end

Given('the caller has an unknown actor marker') do
  @environment.merge!('RIDDIM_ACTOR' => 'crew')
end

Given('the command runs from the worker worktree') do
  @working_directory = @worktree
end

Given('the project checkout is dirty') do
  File.write(File.join(@project, 'tracked.txt'), "operator edit\n")
end

Given('the project checkout is on another branch') do
  git = Open3.capture3('git', '-C', @project, 'switch', '-q', '-c', 'operator-branch').last
  raise 'project checkout could not leave main' unless git.success?
end

# One process-level Git test double per scenario, installed ahead of the real
# Git binary on PATH. The body decides when to act; every invocation
# otherwise continues into the real Git executable found for the scenario.
def install_merge_git_fixture(body)
  real_git = ENV.fetch('PATH').split(File::PATH_SEPARATOR).map { |part| File.join(part, 'git') }
                .find { |path| File.file?(path) && File.executable?(path) }
  raise 'Git executable is required for merge fixtures' unless real_git

  executable = File.join(@herdr_directory, 'git')
  File.write(executable, <<~RUBY)
    #!/usr/bin/ruby
    #{body}
    exec #{real_git.dump}, *ARGV
  RUBY
  File.chmod(0o755, executable)
  @environment.merge!('MERGE_TEST_REAL_GIT' => real_git, 'MERGE_TEST_RECORD' => scenario_record_path('worker'))
end

# Replaces the ownership record with a new generation while the merge command
# is between its record read and its final ownership recheck.
REBIND_DURING_CHECKS = <<~'RUBY'
  if ARGV.include?('--show-toplevel')
    record = ENV.fetch('MERGE_TEST_RECORD')
    staging = "#{record}.replacement"
    File.write(staging, File.read(record).sub(/^spawn_gen=.+$/, 'spawn_gen=s9999.9999.9999'))
    File.rename(staging, record)
  end
RUBY

Given('Git replaces the ownership record during the merge checks') do
  install_merge_git_fixture(REBIND_DURING_CHECKS)
end

# Replaces the ownership record while Git's fast-forward itself is running.
REBIND_DURING_MERGE = <<~'RUBY'
  if ARGV.include?('merge')
    record = ENV.fetch('MERGE_TEST_RECORD')
    staging = "#{record}.replacement"
    File.write(staging, File.read(record).sub(/^spawn_gen=.+$/, 'spawn_gen=s9999.9999.9999'))
    File.rename(staging, record)
  end
RUBY

Given('Git replaces the ownership record during the fast-forward') do
  install_merge_git_fixture(REBIND_DURING_MERGE)
end

# After the fast-forward succeeds, a cooperating writer attempts to claim the
# per-name lock at the next Git call. Riddim must still hold that lock.
MERGE_LOCK_RACE = <<~RUBY
  require 'open3'
  if ARGV.include?('merge')
    stdout, stderr, status = Open3.capture3(ENV.fetch('MERGE_TEST_REAL_GIT'), *ARGV)
    File.write(ENV.fetch('MERGE_TEST_MERGED'), '') if status.success?
    print stdout
    warn stderr unless stderr.empty?
    exit status.exitstatus
  end
  if File.exist?(ENV.fetch('MERGE_TEST_MERGED'))
    File.delete(ENV.fetch('MERGE_TEST_MERGED'))
    File.open(ENV.fetch('MERGE_TEST_LOCK'), File::RDWR | File::NOFOLLOW) do |file|
      if file.flock(File::LOCK_EX | File::LOCK_NB)
        File.write(ENV.fetch('MERGE_TEST_CLAIMED'), '')
      else
        File.write(ENV.fetch('MERGE_TEST_BLOCKED'), '')
      end
    end
  end
RUBY

Given('a competing writer attempts to claim the name during the fast-forward') do
  install_merge_git_fixture(MERGE_LOCK_RACE)
  @merged_marker = File.join(@herdr_directory, 'merged')
  @blocked_writer = File.join(@herdr_directory, 'writer-blocked')
  @claimed_writer = File.join(@herdr_directory, 'writer-claimed')
  @environment.merge!(
    'MERGE_TEST_MERGED' => @merged_marker, 'MERGE_TEST_LOCK' => File.join(scenario_state_dir, '.meta-worker.lock'),
    'MERGE_TEST_BLOCKED' => @blocked_writer, 'MERGE_TEST_CLAIMED' => @claimed_writer
  )
end

# Logs every Git invocation beside the double, so a scenario can assert which
# Git operations the merge command performed.
MERGE_GIT_LOG = <<~'RUBY'
  File.open(File.expand_path('git-invocations', __dir__), 'a') do |file|
    file.write(ARGV.join(' ') + "\n")
  end
RUBY

Given('Git records every invocation during the merge') do
  install_merge_git_fixture(MERGE_GIT_LOG)
end

def merge_git_invocations
  log = File.join(@herdr_directory, 'git-invocations')
  File.exist?(log) ? File.read(log).lines.map(&:strip).reject(&:empty?) : []
end

def local_main_tip
  output, status = Open3.capture2('git', '-C', @project, 'rev-parse', 'refs/heads/main')
  raise 'local main tip could not be read' unless status.success?

  output.strip
end

When('I run riddim merge-local with the approved head') do
  @herdr_calls_before = herdr_invocations.length
  @main_before = local_main_tip
  @stdout, @stderr, @status = run_riddim('merge-local', 'worker', '--head', @approved_head)
end

def merge_success_line
  "merged riddim/worker into local main (#{@main_before} -> #{@approved_head}) in #{@project}\n"
end

Then('merge-local moves local main to the approved tip and reports the exact tips') do
  assert_equal [true, @approved_head, true, true],
               [@status.success?, local_main_tip, @stdout == merge_success_line,
                herdr_invocations.length == @herdr_calls_before], @stderr
end

Then('merge-local refuses a stale reviewed head without moving local main') do
  assert_equal [false, @main_before, true],
               [@status.success?, local_main_tip, @stderr.include?('does not match the worker branch tip')], @stderr
end

Then('merge-local refuses changed ownership without moving local main') do
  assert_equal [false, @main_before, true],
               [@status.success?, local_main_tip, @stderr.include?('ownership changed before the merge')], @stderr
end

Then('merge-local reports the landed main without claiming a verified merge') do
  assert_equal [false, @approved_head, true, true],
               [@status.success?, local_main_tip, @stderr.include?('ownership changed during the merge'),
                @stderr.include?(@approved_head)], @stderr
end

Then('merge-local keeps the name locked through the fast-forward and lands the approved tip') do
  assert_equal [true, @approved_head, true, false, false],
               [@status.success?, local_main_tip, File.exist?(@blocked_writer), File.exist?(@claimed_writer),
                File.read(scenario_record_path('worker')).include?('spawn_gen=s9999.9999.9999')], @stderr
end

Then('merge-local refuses the branch actor without moving local main') do
  assert_equal [false, @main_before, true],
               [@status.success?, local_main_tip, @stderr.include?('never lands local-only work')], @stderr
end

Then('merge-local refuses the unknown actor without moving local main') do
  assert_equal [false, @main_before, true],
               [@status.success?, local_main_tip, @stderr.include?('unknown RIDDIM_ACTOR')], @stderr
end

Then('merge-local refuses the wrong checkout without moving local main') do
  assert_equal [false, @main_before, true],
               [@status.success?, local_main_tip, @stderr.include?('recorded project')], @stderr
end

Then('merge-local refuses the dirty project without moving local main') do
  assert_equal [false, @main_before, true],
               [@status.success?, local_main_tip, @stderr.include?('project has uncommitted work')], @stderr
end

Then('merge-local refuses a project checkout off local main without moving it') do
  assert_equal [false, @main_before, true],
               [@status.success?, local_main_tip, @stderr.include?('project checkout is not on main')], @stderr
end

Then('merge-local refuses the dirty worker without moving local main') do
  assert_equal [false, @main_before, true],
               [@status.success?, local_main_tip, @stderr.include?('worker has uncommitted work')], @stderr
end

Then('merge-local refuses the diverged branch without moving local main') do
  assert_equal [false, @main_before, true],
               [@status.success?, local_main_tip, @stderr.include?('not a fast-forward of local main')], @stderr
end

Then('merge-local refuses the already-landed branch without moving local main') do
  assert_equal [false, @main_before, true],
               [@status.success?, local_main_tip, @stderr.include?('already in local main')], @stderr
end

Then('merge-local refuses without an ungated done report') do
  assert_equal [false, @main_before, true],
               [@status.success?, local_main_tip, @stderr.include?('ungated done report')], @stderr
end

Then('merge-local refuses the open decision gate') do
  assert_equal [false, @main_before, true],
               [@status.success?, local_main_tip, @stderr.include?('ungated done report')], @stderr
end

Then('merge-local lands the tip while Herdr, remotes, and worker assets stay untouched') do
  assert_equal [true, @approved_head, @approved_head, true, true, true, 'done [at=123]: work committed',
                @herdr_calls_before, true],
               [@status.success?, local_main_tip, worker_branch_tip, File.directory?(@worktree),
                File.file?(scenario_record_path('worker')), File.file?(File.join(scenario_state_dir, 'worker.brief')),
                File.read(@result_path).lines.last&.strip, herdr_invocations.length,
                merge_git_invocations.none? { |line| line.match?(/\b(?:fetch|push|worktree|branch)\b/) }], @stderr
end

Then('merge-local rejects a short head before reading any state') do
  assert_equal [2, '', true], [@status.exitstatus, @stdout, @stderr.include?('Usage: riddim merge-local')]
end

Then('merge-local refuses without an ownership record') do
  assert_equal [false, '', true], [@status.success?, @stdout, @stderr.include?('no endpoint record exists')]
end

Then('merge-local refuses a non-local task') do
  assert_equal [false, '', true], [@status.success?, @stdout, @stderr.include?('only for local-only tasks')]
end
