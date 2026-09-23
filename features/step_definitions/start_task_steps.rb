# frozen_string_literal: true

require_relative '../../lib/riddim/task_brief'

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

Then('Pi receives a pointer to the published worker brief as its initial prompt') do
  brief = File.join(scenario_state_dir, 'worker.brief')
  pointer = File.binread(File.join(@herdr_directory, 'initial-brief'))
  requested = "Fix Riddim's worktree test. Keep the user's instructions intact.\nRun the full test suite."
  content = File.binread(brief)
  assert_equal [true, "Read the brief at #{brief} and follow it exactly.", true, true, true, true],
               [@status.success?, pointer, content.include?(requested),
                content.include?('You are a coding worker'), content.include?('AGENTS.md'),
                File.stat(brief).mode & 0o777 == 0o600]
end

Then('the failed task retains its brief and linked worktree') do
  assert_equal [false, true, true], [@status.success?, File.file?(File.join(scenario_state_dir, 'worker.brief')),
                                     File.directory?(@worktree)]
end
