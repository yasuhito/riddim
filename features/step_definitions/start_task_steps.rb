# frozen_string_literal: true

require_relative '../../lib/riddim/task_brief'

Given('a fake Pi executable is on PATH for the task launch') do
  bin = File.join(@herdr_directory, 'pi-bin')
  FileUtils.mkdir_p(bin)
  executable = File.join(bin, 'pi')
  File.write(executable, "#!/bin/sh\nexit 0\n")
  File.chmod(0o755, executable)
  @environment['PATH'] = "#{bin}:#{@environment.fetch('PATH')}"
  unless @environment.fetch('PATH').split(File::PATH_SEPARATOR).include?(@herdr_directory)
    raise 'fake Herdr is not on PATH'
  end
end

Given('Pi trace is enabled for task launch') do
  @environment['RIDDIM_PI_TRACE'] = '1'
end

Given('a task file containing:') do |body|
  File.write(File.join(@project, 'task.md'), body)
end

Given('a symlinked task file') do
  File.symlink(File.join(@project, 'tracked.txt'), File.join(@project, 'task.md'))
end

Given('a task file with invalid UTF-8') do
  File.binwrite(File.join(@project, 'task.md'), "\xff".b)
end

Given('a task file larger than the brief limit') do
  File.write(File.join(@project, 'task.md'), 'a' * (Riddim::TaskBrief::MAX_BYTES + 1))
end

Given('an existing worker brief') do
  FileUtils.mkdir_p(scenario_state_dir)
  File.write(File.join(scenario_state_dir, 'worker.brief'), 'keep')
end

Given('the shell launch submission is unconfirmed') do
  File.write(File.join(@herdr_directory, 'shell-submit-fails'), '')
end

Given('the new pane does not register Pi') do
  File.write(File.join(@herdr_directory, 'unrecognized-pi'), '')
end

Given('the new named Pi belongs to another incarnation') do
  File.write(File.join(@herdr_directory, 'replaced-pi'), '')
end

Given('the new Pi cannot be named') do
  File.write(File.join(@herdr_directory, 'rename-fails'), '')
end

def last_task_source_line
  invocation = herdr_invocations.grep(/ pane run w9:p1 \. /).last
  raise 'no submitted task launch line' unless invocation

  invocation.split('pane run w9:p1 ', 2).last
end

When('I restart the worker with a different task after inspecting and removing its old resources') do
  @first_stdout, @first_stderr, @first_status = run_riddim('start', 'worker', '--worktree', '--task-file', 'task.md')
  raise "first start failed: #{@first_stderr}" unless @first_status.success?

  @first_source_line = last_task_source_line
  @first_generation = File.read(scenario_record_path('worker'))[/^spawn_gen=(.+)$/, 1]
  File.delete(scenario_record_path('worker'))
  File.delete(File.join(scenario_state_dir, 'worker.brief'))
  File.delete(@first_source_line.delete_prefix('. '))
  git = ->(*args) { Open3.capture3('git', '-C', @project, *args) }
  raise 'old worktree could not be removed' unless git.call('worktree', 'remove', @worktree).last.success?
  raise 'old branch could not be removed' unless git.call('branch', '-d', 'riddim/worker').last.success?

  %w[agent-named launch-submitted].each do |marker|
    File.delete(File.join(@herdr_directory, marker))
  end
  File.write(File.join(@project, 'task.md'), 'Replacement task.')
  @stdout, @stderr, @status = run_riddim('start', 'worker', '--worktree', '--task-file', 'task.md')
  @second_source_line = last_task_source_line if @status.success?
end

Then('the original source line cannot launch the replacement task') do
  @second_generation = File.read(scenario_record_path('worker'))[/^spawn_gen=(.+)$/, 1] if @status.success?
  _stdout, _stderr, delayed_status = Open3.capture3('/bin/sh', '-c', @first_source_line, chdir: @worktree)
  assert_equal [true, true, true, true, true, false],
               [@status.success?, @first_generation != @second_generation,
                @first_source_line.include?(".launch.#{@first_generation}.sh"),
                @second_source_line.include?(".launch.#{@second_generation}.sh"),
                @first_source_line != @second_source_line, delayed_status.success?], @stderr
end

Then('Pi receives a staged full brief launch and is named on its exact pane') do
  brief = File.join(scenario_state_dir, 'worker.brief')
  staged = File.join(@herdr_directory, 'staged-launch')
  script = File.file?(staged) ? File.binread(staged) : "missing launch: #{@stderr}"
  content = File.binread(brief)
  requested = "Fix Riddim's worktree test. Keep the user's instructions intact.\nRun the full test suite."
  assert_equal [true, true, true, true, true, true, true, true, false],
               [@status.success?, script.include?('export RIDDIM_ACTOR=branch'),
                script.include?('$(/usr/bin/cat -- '), script.include?(brief),
                content.include?(requested), content.include?('You are a coding worker'),
                File.stat(brief).mode & 0o777 == 0o600,
                herdr_invocations.any? { |line| line.include?('agent rename w9:p1 worker') },
                script.start_with?('exec ')], "#{@stderr}\n#{herdr_invocations.inspect}"
end

Then('the staged launch enables a generation-bound Pi trace') do
  gen = File.read(scenario_record_path('worker'))[/^spawn_gen=(.+)$/, 1]
  trace = File.join(scenario_state_dir, "worker.brief.trace.#{gen}.jsonl")
  script = File.binread(File.join(@herdr_directory, 'staged-launch'))
  assert_equal [true, true, true, false],
               [@status.success?, script.include?('pi_stall_trace.ts'), script.include?(trace), File.exist?(trace)]
end

Then('the failed task retains its brief, record, pane, and linked worktree') do
  assert_equal [false, true, true, true, false],
               [@status.success?, File.file?(File.join(scenario_state_dir, 'worker.brief')),
                File.file?(scenario_record_path('worker')), File.directory?(@worktree),
                herdr_invocations.any? { |line| line.include?('pane close w9:p1') }]
end
