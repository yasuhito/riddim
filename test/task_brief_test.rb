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

  # Publishes a launch through TaskBrief.publish_launch with the fake Pi on
  # PATH, so publication tests never depend on a real Pi installation.
  def publish_launch(profile, spawn_gen)
    old_path = ENV.fetch('PATH')
    ENV['PATH'] = "#{@bin}:#{old_path}"
    Riddim::TaskBrief.publish_launch(Riddim::TaskBrief::Brief.new(@brief_path, ''), profile, spawn_gen)
  ensure
    ENV['PATH'] = old_path
  end

  # Publishes through TaskBrief.publish_launch and returns the raised
  # TaskBrief::Error, or nil when the publication succeeds.
  def launch_rejection(profile, spawn_gen)
    publish_launch(profile, spawn_gen)
    nil
  rescue Riddim::TaskBrief::Error => e
    e
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

  def test_publish_launch_rejects_a_path_traversal_spawn_gen_before_publishing_anything
    rejection_error = launch_rejection(Riddim::AgentProfile.parse('pi safe max'), '../../escape')

    assert_equal [Riddim::TaskBrief::Error, 'task launch requires a valid spawn generation',
                  false, %w[worker.brief]],
                 [rejection_error&.class, rejection_error&.message,
                  File.exist?(File.join(@root, 'escape.sh')), Dir.children(@private_dir).sort]
  end

  def test_publish_launch_rejects_every_invalid_spawn_gen_shape_before_publishing
    profile = Riddim::AgentProfile.parse('pi safe max')
    invalid = [nil, 17, '', 's1.2', '1.2.3', 's1.2.3.4', "s1.2.3\n", '/s1.2.3']
    messages = invalid.map { |spawn_gen| launch_rejection(profile, spawn_gen)&.message }

    assert_equal [Array.new(invalid.size, 'task launch requires a valid spawn generation'), %w[worker.brief]],
                 [messages, Dir.children(@private_dir).sort]
  end

  def test_publish_launch_refuses_to_replace_a_launch_file_for_the_same_generation
    gen = 's1767200000.4242.7'
    published = publish_launch(Riddim::AgentProfile.parse('pi safe max'), gen)
    original_bytes = File.binread(published)
    replacement_error = launch_rejection(Riddim::AgentProfile.parse('pi model$(touchPWNED) low'), gen)

    assert_equal [Riddim::TaskBrief::Error, true, original_bytes],
                 [replacement_error&.class, replacement_error&.message&.include?('already exists'),
                  File.binread(published)]
  end

  def test_published_launch_filename_carries_the_spawn_generation
    gen = 's1767200000.4242.7'
    path = publish_launch(Riddim::AgentProfile.parse('pi safe max'), gen)

    assert_equal [File.join(@private_dir, "worker.brief.launch.#{gen}.sh"), true],
                 [path, File.exist?(path)]
  end

  def test_launch_source_marks_the_task_pi_as_a_branch_actor
    source = with_fake_pi_path do
      Riddim::TaskBrief.launch_source(Riddim::TaskBrief::Brief.new(@brief_path, ''),
                                      Riddim::AgentProfile.parse('pi safe max'))
    end

    assert source.start_with?("export RIDDIM_ACTOR=branch\n")
  end

  def with_fake_pi_path
    old_path = ENV.fetch('PATH')
    ENV['PATH'] = "#{@bin}:#{old_path}"
    yield
  ensure
    ENV['PATH'] = old_path
  end
end
