# frozen_string_literal: true

require 'json'

Given('Herdr serves the recorded pane and Pi registration') do
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['pane', 'get']
      file = File.expand_path('pane-response', __dir__)
      print(File.file?(file) ? File.read(file) : #{PANE_PRESENT_RESPONSE.dump})
      exit 1 if File.exist?(File.expand_path('pane-error', __dir__))
    when ['agent', 'get']
      file = File.expand_path('agent-response', __dir__)
      payload = File.file?(file) ? File.read(file) : #{pi_agent_response.dump}
      output = File.exist?(File.expand_path('agent-stderr', __dir__)) ? $stderr : $stdout
      print 'unexpected output' if File.exist?(File.expand_path('agent-stdout-garbage', __dir__))
      output.print(payload)
      exit 1 if File.exist?(File.expand_path('agent-error', __dir__))
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('ownership is rebound while Herdr reads the agent') do
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['pane', 'get'] then puts #{PANE_PRESENT_RESPONSE.dump}
    when ['agent', 'get']
      path = File.join(ENV.fetch('RIDDIM_STATE_DIR'), 'worker.meta')
      lock = File.join(ENV.fetch('RIDDIM_STATE_DIR'), '.meta-worker.lock')
      File.open(lock, File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        bytes = File.read(path).sub('spawn_gen=s1767200000.4242.7', 'spawn_gen=s1767200001.4242.8')
        staging = "\#{path}.replacement"
        File.write(staging, bytes)
        File.rename(staging, path)
      end
      puts #{pi_agent_response.dump}
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('the pane foreground is neither Pi nor a shell') do
  File.write(File.join(@herdr_directory, 'other-pi'), '')
end

Given("Herdr's registered agent names pane {string}") do |pane|
  File.write(File.join(@herdr_directory, 'agent-response'), pi_agent_response(pane_id: pane))
end

Given("Herdr's registered agent is not Pi") do
  File.write(File.join(@herdr_directory, 'agent-response'), pi_agent_response(kind: 'codex'))
end

Given('Herdr reports no agent on standard error') do
  response = JSON.generate(error: { code: 'agent_not_found', message: 'agent not found' })
  File.write(File.join(@herdr_directory, 'agent-response'), response)
  File.write(File.join(@herdr_directory, 'agent-error'), '')
  File.write(File.join(@herdr_directory, 'agent-stderr'), '')
end

Given('Herdr emits unrelated stdout with a not-found error on stderr') do
  response = JSON.generate(error: { code: 'agent_not_found', message: 'agent not found' })
  File.write(File.join(@herdr_directory, 'agent-response'), response)
  %w[agent-error agent-stderr agent-stdout-garbage].each do |marker|
    File.write(File.join(@herdr_directory, marker), '')
  end
end

Given('Herdr reports an unknown agent status') do
  File.write(File.join(@herdr_directory, 'agent-response'), pi_agent_response(status: 'unknown'))
end

Given('Herdr has no registered agent in the pane') do
  response = JSON.generate(error: { code: 'agent_not_found', message: 'agent not found' })
  File.write(File.join(@herdr_directory, 'agent-response'), response)
  File.write(File.join(@herdr_directory, 'agent-error'), '')
end

Given('Herdr reports the pane was not found') do
  File.write(File.join(@herdr_directory, 'pane-response'), PANE_NOT_FOUND_RESPONSE)
  File.write(File.join(@herdr_directory, 'pane-error'), '')
end

Given('Herdr cannot read the pane') do
  File.write(File.join(@herdr_directory, 'pane-response'), 'unavailable')
  File.write(File.join(@herdr_directory, 'pane-error'), '')
end

Given("Herdr's pane response has a non-object result") do
  File.write(File.join(@herdr_directory, 'pane-response'), JSON.generate(result: []))
end

Given('Herdr replies with malformed pane JSON') do
  File.write(File.join(@herdr_directory, 'pane-response'), 'malformed JSON')
end

Given('the recorded Herdr server is {word}') do |state|
  status = { client: { protocol: 22, version: '0.9.0' }, server: { running: state == 'running' } }
  File.write(File.join(@herdr_directory, 'client-status.json'), JSON.generate(status))
end
