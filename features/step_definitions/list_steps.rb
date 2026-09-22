# frozen_string_literal: true

require 'fileutils'

Given('a state directory symlink') do
  target = new_temporary_directory
  File.symlink(target, scenario_state_dir)
end

Given('a record filename containing invalid UTF-8') do
  FileUtils.mkdir_p(scenario_state_dir)
  File.binwrite(File.join(scenario_state_dir, "\xFF.meta".b), 'not a record')
end

Given('a malformed record filename') do
  FileUtils.mkdir_p(scenario_state_dir)
  File.write(File.join(scenario_state_dir, 'bad name.meta'), 'not a record')
end

Given('a staged record that was never published') do
  FileUtils.mkdir_p(scenario_state_dir)
  File.write(File.join(scenario_state_dir, '.worker.meta.spawn.123'), 'not a record')
end

Given('an empty state directory') do
  FileUtils.mkdir_p(scenario_state_dir)
end

Then('standard output is the sorted endpoint list') do
  assert_equal "alpha\triddim\tw9:p1\nzeta\tsecondary\tw8:p1\n", @stdout
end
