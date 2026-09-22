# frozen_string_literal: true

Given('Herdr reports native agent status {string}') do |status|
  File.write(File.join(@herdr_directory, 'agent-response'), pi_agent_response(status: status))
end
