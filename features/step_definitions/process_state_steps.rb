# frozen_string_literal: true

Given("Herdr's process view names a different pane") do
  File.write(File.join(@herdr_directory, 'wrong-process-pane'), '')
end

Given('Herdr reports no foreground processes for the recorded pane') do
  File.write(File.join(@herdr_directory, 'empty-foreground'), '')
end

Given('ownership is rebound while Herdr reads the process view') do
  File.write(File.join(@herdr_directory, 'rebind-record'), '')
end

Then('Herdr reads only the exact recorded process view') do
  assert_equal ['--session riddim pane process-info --pane w9:p1'], herdr_invocations
end
