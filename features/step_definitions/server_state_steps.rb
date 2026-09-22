# frozen_string_literal: true

require 'json'

Given('Herdr reports unreadable status JSON') do
  File.write(File.join(@herdr_directory, 'client-status.json'), 'not JSON')
end

Given('Herdr reports no server field in its status') do
  File.write(File.join(@herdr_directory, 'client-status.json'), JSON.generate(client: { version: '0.9.0' }))
end

Given('Herdr fails its status read') do
  File.write(File.join(@herdr_directory, 'client-status.json'), JSON.generate(server: { running: true }))
  File.write(File.join(@herdr_directory, 'status-fails'), '')
end

Given('ownership is rebound while Herdr reads the status') do
  File.write(File.join(@herdr_directory, 'rebind-record'), '')
end

Then('Herdr reads only the recorded session status') do
  assert_equal ['--session riddim status --json'], herdr_invocations
end
