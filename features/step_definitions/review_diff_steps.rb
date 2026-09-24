# frozen_string_literal: true

Given('the recorded worker worktree is a symlink') do
  alias_path = File.join(File.dirname(@worktree), 'worker-alias')
  File.symlink(@worktree, alias_path)
  path = scenario_record_path('worker')
  File.write(path, File.read(path).sub("worktree=#{@worktree}", "worktree=#{alias_path}"))
end

Given('Git replaces the ownership record while preparing the review') do
  directory = new_temporary_directory
  git = ENV.fetch('PATH').split(File::PATH_SEPARATOR).map { |part| File.join(part, 'git') }
           .find { |path| File.file?(path) && File.executable?(path) }
  raise 'Git executable is required for review fixtures' unless git

  record = scenario_record_path('worker')
  executable = File.join(directory, 'git')
  File.write(executable, <<~RUBY)
    #!/usr/bin/ruby
    if ARGV.include?('diff')
      path = #{record.dump}
      replacement = File.read(path).sub(/^spawn_gen=.+$/, 'spawn_gen=s9999.9999.9999')
      staging = "\#{path}.replacement"
      File.write(staging, replacement)
      File.rename(staging, path)
    end
    exec #{git.dump}, *ARGV
  RUBY
  File.chmod(0o755, executable)
  @environment['PATH'] = "#{directory}:#{ENV.fetch('PATH')}"
end

# The fake Git first completes the patch, then asks a cooperating record
# writer to acquire the name lock during the following Git check.
REVIEW_RACE_GIT = <<~'RUBY'
  #!/usr/bin/ruby
  require 'open3'
  real_git = ENV.fetch('REVIEW_TEST_REAL_GIT')
  marker = ENV.fetch('REVIEW_TEST_MARKER')
  if ARGV.include?('diff') && !ARGV.include?('--stat')
    stdout, stderr, status = Open3.capture3(real_git, *ARGV)
    File.write(marker, '') if status.success?
    print stdout
    warn stderr unless stderr.empty?
    exit status.exitstatus
  end
  if File.exist?(marker)
    File.delete(marker)
    File.open(ENV.fetch('REVIEW_TEST_LOCK'), File::RDWR | File::NOFOLLOW) do |file|
      if file.flock(File::LOCK_EX | File::LOCK_NB)
        path = ENV.fetch('REVIEW_TEST_RECORD')
        replacement = File.read(path).sub(/^spawn_gen=.+$/, 'spawn_gen=s9999.9999.9999')
        staging = "#{path}.replacement"
        File.write(staging, replacement)
        File.rename(staging, path)
      else
        File.write(ENV.fetch('REVIEW_TEST_BLOCKED'), '')
      end
    end
  end
  exec real_git, *ARGV
RUBY

Given('a competing writer attempts to rebind ownership during the final Git check') do
  directory = new_temporary_directory
  git = ENV.fetch('PATH').split(File::PATH_SEPARATOR).map { |part| File.join(part, 'git') }
           .find { |path| File.file?(path) && File.executable?(path) }
  raise 'Git executable is required for review fixtures' unless git

  executable = File.join(directory, 'git')
  File.write(executable, REVIEW_RACE_GIT)
  File.chmod(0o755, executable)
  @blocked_writer = File.join(directory, 'writer-blocked')
  @environment.merge!(
    'PATH' => "#{directory}:#{ENV.fetch('PATH')}", 'REVIEW_TEST_REAL_GIT' => git,
    'REVIEW_TEST_LOCK' => File.join(scenario_state_dir, '.meta-worker.lock'),
    'REVIEW_TEST_RECORD' => scenario_record_path('worker'),
    'REVIEW_TEST_MARKER' => File.join(directory, 'after-patch'), 'REVIEW_TEST_BLOCKED' => @blocked_writer
  )
end

Given('the worker checkout is detached') do
  _output, status = Open3.capture2e('git', '-C', @worktree, 'switch', '--detach', '-q', 'HEAD')
  raise 'worker checkout could not be detached' unless status.success?
end

Then('review-diff refuses without an ownership record') do
  assert_equal [false, '', true], [@status.success?, @stdout, @stderr.include?('no endpoint record exists')]
end

Then('review-diff refuses a non-local task') do
  assert_equal [false, '', true], [@status.success?, @stdout, @stderr.include?('only for local-only tasks')]
end

Then('review-diff reports no changes against local main') do
  assert_equal [true, "diff base: main\nhead: #{@worker_tip}\nno changes vs main\n"],
               [@status.success?, @stdout], @stderr
end

Then("review-diff shows the worker's committed patch against local main") do
  assert_equal [true, true, true, true, true],
               [@status.success?, @stdout.start_with?("diff base: main\n"),
                @stdout.include?("head: #{@worker_tip}\n"), @stdout.include?('tracked.txt |'),
                @stdout.include?("+worker change\n")], @stderr
end

Then("review-diff shows only the worker's change statistics") do
  assert_equal [true, true, true, false],
               [@status.success?, @stdout.include?("head: #{@worker_tip}\n"),
                @stdout.include?('tracked.txt |'), @stdout.include?('diff --git')], @stderr
end

Then('review-diff refuses changed ownership without printing a patch') do
  assert_equal [false, '', true], [@status.success?, @stdout, @stderr.include?('ownership changed')]
end

Then('review-diff keeps the original owner until the diff is displayed') do
  record = File.read(scenario_record_path('worker'))
  assert_equal [true, true, true, true],
               [@status.success?, @stdout.include?("+worker change\n"),
                File.exist?(@blocked_writer), !record.include?('spawn_gen=s9999.9999.9999')], @stderr
end

Then('review-diff refuses an untrusted worktree without printing a patch') do
  assert_equal [false, '', true], [@status.success?, @stdout, @stderr.include?('linked checkout')]
end

Then('review-diff rejects the option before touching a worktree') do
  assert_equal [2, '', true], [@status.exitstatus, @stdout, @stderr.include?('Usage: riddim review-diff')]
end

Then('review-diff refuses an unbound branch without printing a patch') do
  assert_equal [false, '', true], [@status.success?, @stdout, @stderr.include?('worker branch')]
end
