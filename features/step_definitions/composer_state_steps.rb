# frozen_string_literal: true

require 'fileutils'
require 'json'

COMPOSER_SEPARATOR = '─' * 12

# The composer fake's identity probe: a fixture when present, a failure
# (the adapter's probe-absent) otherwise.
IDENTITY_PROBE_FIXTURE = <<~RUBY
  file = File.expand_path('agent-identity', __dir__)
  unless File.file?(file)
    warn 'herdr: agent not found'
    exit 1
  end
  print File.read(file)
  exit 0
RUBY

# Installs the composer-screen Herdr test double: marker files drive which
# captures fail, and the identity probe reads a fixture or fails closed.
Given('Herdr serves composer screens') do
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['pane', 'read']
      #{REBIND_RECORD_FIXTURE}
      if File.exist?(File.expand_path('reads-fail', __dir__))
        warn 'herdr: read failed'
        exit 1
      end
      ansi = ARGV.include?('--format')
      if ansi && File.exist?(File.expand_path('ansi-fails', __dir__))
        warn 'herdr: read failed'
        exit 1
      end
      file = File.expand_path(ansi ? 'styled-screen' : 'plain-screen', __dir__)
      print(File.file?(file) ? File.read(file) : '')
      exit 0
    when ['agent', 'get'] then #{IDENTITY_PROBE_FIXTURE}    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('the styled composer capture is:') do |text|
  File.write(File.join(@herdr_directory, 'styled-screen'), text)
end

Given('the plain composer capture is:') do |text|
  File.write(File.join(@herdr_directory, 'plain-screen'), text)
end

Given('the styled composer capture is dim placeholder inside a pair') do
  File.write(File.join(@herdr_directory, 'styled-screen'),
             "#{COMPOSER_SEPARATOR}\n\e[2mType a message\e[0m\n#{COMPOSER_SEPARATOR}\n")
end

Given('the styled composer capture holds nine inner rows') do
  inner = "row of typed input\n" * 9
  File.write(File.join(@herdr_directory, 'styled-screen'), "#{COMPOSER_SEPARATOR}\n#{inner}#{COMPOSER_SEPARATOR}\n")
end

Given('the styled composer capture is a dim placeholder beside bright input') do
  inner = "\e[2mType a message\e[0m\nalso typed\n"
  File.write(File.join(@herdr_directory, 'styled-screen'), "#{COMPOSER_SEPARATOR}\n#{inner}#{COMPOSER_SEPARATOR}\n")
end

Given('the styled composer capture ends below the pair:') do |tail|
  File.write(File.join(@herdr_directory, 'styled-screen'), "#{COMPOSER_SEPARATOR}\n\n#{COMPOSER_SEPARATOR}\n#{tail}")
end

Given('Herdr fails every composer read') do
  File.write(File.join(@herdr_directory, 'reads-fail'), '')
end

Given('Herdr fails the styled composer read only') do
  File.write(File.join(@herdr_directory, 'ansi-fails'), '')
end

Given('ownership is rebound while Herdr reads the composer') do
  File.write(File.join(@herdr_directory, 'rebind-record'), '')
end

Given('the identity probe reports pi as {word}') do |agent_status|
  identity = JSON.generate(result: { agent: { agent: 'pi', agent_status: agent_status } })
  File.write(File.join(@herdr_directory, 'agent-identity'), identity)
end

Given('the identity probe reports a foreign agent') do
  identity = JSON.generate(result: { agent: { agent: 'claude', agent_status: 'idle' } })
  File.write(File.join(@herdr_directory, 'agent-identity'), identity)
end

Given('the identity probe finds no agent') do
  FileUtils.rm_f(File.join(@herdr_directory, 'agent-identity'))
end

Given('the identity probe replies with malformed JSON') do
  File.write(File.join(@herdr_directory, 'agent-identity'), 'not JSON')
end

Then('Herdr reads only the styled composer capture') do
  expected = ['--session riddim pane read w9:p1 --source recent --lines 200 --format ansi']

  assert_equal expected, herdr_invocations
end

Then('Herdr reads the composer capture and the identity probe') do
  expected = [
    '--session riddim pane read w9:p1 --source recent --lines 200 --format ansi',
    '--session riddim agent get w9:p1'
  ]

  assert_equal expected, herdr_invocations
end

Then('Herdr reads the plain fallback capture first') do
  expected = [
    '--session riddim pane read w9:p1 --source recent --lines 200 --format ansi',
    '--session riddim pane read w9:p1 --source recent --lines 200',
    '--session riddim agent get w9:p1'
  ]

  assert_equal expected, herdr_invocations
end
