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
  assert_equal [true, "diff base: main\nno changes vs main\n"], [@status.success?, @stdout], @stderr
end

Then("review-diff shows the worker's committed patch against local main") do
  assert_equal [true, true, true, true],
               [@status.success?, @stdout.start_with?("diff base: main\n"),
                @stdout.include?('tracked.txt |'), @stdout.include?("+worker change\n")], @stderr
end

Then("review-diff shows only the worker's change statistics") do
  assert_equal [true, true, false],
               [@status.success?, @stdout.include?('tracked.txt |'), @stdout.include?('diff --git')], @stderr
end

Then('review-diff refuses changed ownership without printing a patch') do
  assert_equal [false, '', true], [@status.success?, @stdout, @stderr.include?('ownership changed')]
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
