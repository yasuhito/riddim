# frozen_string_literal: true

require 'json'

# Fake pane.get reports both fields so a stale creation cwd cannot pass for
# the foreground process's current directory.
def pane_with_paths(creation:, foreground:, pane: 'w9:p1', include_foreground: true)
  details = { pane_id: pane, cwd: creation }
  details[:foreground_cwd] = foreground if include_foreground
  JSON.generate(result: { type: 'pane_info', pane: details })
end

Given('the pane was created in {string} and its foreground is in {string}') do |creation, foreground|
  File.write(File.join(@herdr_directory, 'pane-response'), pane_with_paths(creation: creation, foreground: foreground))
end

Given("Herdr's pane only reports creation path {string}") do |creation|
  body = pane_with_paths(creation: creation, foreground: nil, include_foreground: false)
  File.write(File.join(@herdr_directory, 'pane-response'), body)
end

Given("Herdr's pane reports no foreground path and creation path {string}") do |creation|
  File.write(File.join(@herdr_directory, 'pane-response'), pane_with_paths(creation: creation, foreground: nil))
end

Given("Herdr's pane foreground path contains a newline") do
  body = pane_with_paths(creation: '/created', foreground: "/line\nbreak")
  File.write(File.join(@herdr_directory, 'pane-response'), body)
end

Given("Herdr's other pane reports foreground path {string}") do |foreground|
  body = pane_with_paths(creation: '/created', foreground: foreground, pane: 'w9:p2')
  File.write(File.join(@herdr_directory, 'pane-response'), body)
end

Given('ownership is rebound while Herdr reads the foreground path') do
  body = pane_with_paths(creation: '/created', foreground: '/live')
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
    puts #{body.dump}
  RUBY
end
