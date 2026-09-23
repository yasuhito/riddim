# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'shellwords'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/riddim/task_brief'
require_relative '../lib/riddim/profile'

class TaskBriefLaunchTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir
    @private_dir = File.join(@root, "brief's $(touch PWNED)")
    @bin = File.join(@root, 'bin')
    FileUtils.mkdir_p([@private_dir, @bin])
    @brief_path = File.join(@private_dir, 'worker.brief')
    @launch_path = File.join(@private_dir, 'launch.sh')
    @output = File.join(@root, 'arguments')
    File.write(@brief_path, "Worker role\nTask with ' and $(not-run)\n")
    prepare_fake_pi
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def prepare_fake_pi
    pi = File.join(@bin, 'pi')
    File.write(pi, "#!/bin/sh\nprintf '%s\\0' \"$@\" > #{Shellwords.escape(@output)}\n")
    File.chmod(0o755, pi)
  end

  def run_staged_script(profile)
    old_path = ENV.fetch('PATH')
    ENV['PATH'] = "#{@bin}:#{old_path}"
    brief = Riddim::TaskBrief::Brief.new(@brief_path, '')
    File.write(@launch_path, Riddim::TaskBrief.launch_source(brief, profile))
    Open3.capture3('/bin/sh', '-c', ". #{Shellwords.escape(@launch_path)}", chdir: @root).last
  ensure
    ENV['PATH'] = old_path
  end

  def test_missing_brief_does_not_start_pi
    profile = Riddim::AgentProfile.parse('pi safe max')
    File.delete(@brief_path)
    status = run_staged_script(profile)

    assert_equal [false, false], [status.success?, File.exist?(@output)]
  end

  def test_full_multiline_brief_is_one_shell_safe_pi_argument
    profile = Riddim::AgentProfile.parse('pi model$(touchPWNED) max')
    status = run_staged_script(profile)

    assert_equal [true, ['--model', 'model$(touchPWNED)', '--thinking', 'max',
                         "Worker role\nTask with ' and $(not-run)"], false],
                 [status.success?, File.binread(@output).split("\0"), File.exist?(File.join(@root, 'PWNED'))]
  end
end
