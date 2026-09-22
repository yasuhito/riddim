# frozen_string_literal: true

require 'json'

Given('Herdr returns a different pane id for pane get') do
  body = JSON.generate(result: { type: 'pane_info', pane: { pane_id: 'w9:p2' } })
  File.write(File.join(@herdr_directory, 'pane-response'), body)
end

Given('Herdr returns an unrelated pane error') do
  body = JSON.generate(error: { code: 'server_unavailable', message: 'unavailable' })
  File.write(File.join(@herdr_directory, 'pane-response'), body)
  File.write(File.join(@herdr_directory, 'pane-error'), '')
end

Given('Herdr reports pane not found on stderr with empty stdout') do
  install_fake_herdr(<<~RUBY)
    abort "unexpected invocation: \#{ARGV.join(' ')}" unless ARGV == %w[pane get w9:p1]
    warn #{PANE_NOT_FOUND_RESPONSE.dump}
    exit 1
  RUBY
end

Given('Herdr writes unrelated stdout before a not-found error on stderr') do
  install_fake_herdr(<<~RUBY)
    abort "unexpected invocation: \#{ARGV.join(' ')}" unless ARGV == %w[pane get w9:p1]
    puts 'unexpected output'
    warn #{PANE_NOT_FOUND_RESPONSE.dump}
    exit 1
  RUBY
end

Given('Herdr exits with failure after reporting the matching pane') do
  File.write(File.join(@herdr_directory, 'pane-error'), '')
end

Given('ownership is rebound while Herdr reads the pane') do
  install_fake_herdr(<<~RUBY)
    abort "unexpected invocation: \#{ARGV.join(' ')}" unless ARGV == %w[pane get w9:p1]
    path = File.join(ENV.fetch('RIDDIM_STATE_DIR'), 'worker.meta')
    lock = File.join(ENV.fetch('RIDDIM_STATE_DIR'), '.meta-worker.lock')
    File.open(lock, File::RDWR | File::CREAT, 0o600) do |file|
      file.flock(File::LOCK_EX)
      bytes = File.read(path).sub('spawn_gen=s1767200000.4242.7', 'spawn_gen=s1767200001.4242.8')
      staging = "\#{path}.replacement"
      File.write(staging, bytes)
      File.rename(staging, path)
    end
    puts #{PANE_PRESENT_RESPONSE.dump}
  RUBY
end

Then('Herdr only reads the exact recorded pane') do
  assert_equal ['--session riddim pane get w9:p1'], herdr_invocations
end
