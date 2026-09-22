# frozen_string_literal: true

require 'bundler'
require 'fileutils'
require 'minitest'
require 'minitest/assertions'
require 'open3'
require 'shellwords'
require 'tmpdir'

# Shared filesystem, process, and assertion support for CLI scenarios.
module RiddimWorld
  RIDDIM = File.expand_path('../../bin/riddim', __dir__)

  include Minitest::Assertions

  def assertions
    @assertions ||= 0
  end

  # A fresh temporary directory that is removed after the scenario.
  def new_temporary_directory
    directory = Dir.mktmpdir
    @temporary_directories << directory
    directory
  end

  # Every Herdr invocation the fake executable observed, in order.
  def herdr_invocations
    log = File.join(@herdr_directory, 'invocations')
    File.exist?(log) ? File.read(log).split("\n").reject(&:empty?) : []
  end

  # The Herdr session Riddim resolves for this scenario's child environment:
  # the nonempty HERDR_SESSION value, otherwise Herdr's default session.
  def scenario_session
    value = @environment && @environment['HERDR_SESSION']
    value.is_a?(String) && !value.empty? ? value : 'default'
  end
end

# Appends one line per Herdr invocation to a log beside the fake executable.
LOG_INVOCATION = "File.open(File.expand_path('invocations', __dir__), 'a') { |file| file.puts ARGV.join(' ') }"

# Refuses any invocation that is not session-targeted: HERDR_SESSION must be
# set in the subprocess environment and an explicit --session argument naming
# that same session must come ahead of the subcommand. The stripped session
# pair stays in session_argv for bodies that echo the full invocation; the
# other bodies see the bare operation argv.
SESSION_GUARD = <<~RUBY
  session = ENV.fetch('HERDR_SESSION', nil)
  abort 'riddim: HERDR_SESSION is not set' if session.nil? || session.empty?
  unless ARGV[0, 2] == ['--session', session]
    abort "unverified session: \#{ARGV.join(' ')} (HERDR_SESSION=\#{session.inspect})"
  end
  session_argv = ARGV.shift(2)
RUBY

World(RiddimWorld)

Before do
  @temporary_directories = []
end

After do
  @temporary_directories.each { |directory| FileUtils.remove_entry(directory) }
end
