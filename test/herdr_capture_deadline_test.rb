# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/riddim/herdr'

class HerdrCaptureDeadlineTest < Minitest::Test
  # rubocop:disable-next Metrics/MethodLength
  def setup
    @root = Dir.mktmpdir('riddim-herdr-deadline-')
    @path = ENV.fetch('PATH')
    ENV['PATH'] = "#{@root}:#{@path}"
    File.write(File.join(@root, 'herdr'), <<~RUBY)
      #!#{RbConfig.ruby}
      sleep 0.15 if ARGV.include?('slow')
      if ARGV.include?('inherited-pipe')
        fork { sleep 60 }
        exit! 0
      end
      puts ARGV.join(' ')
      warn ENV.fetch('HERDR_SESSION')
    RUBY
    File.chmod(0o700, File.join(@root, 'herdr'))
  end

  def teardown
    ENV['PATH'] = @path
    FileUtils.remove_entry(@root)
  end

  def clock
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # rubocop:disable-next Metrics/MethodLength, Minitest/MultipleAssertions
  def test_captures_share_one_deadline_and_restore_normal_routing_after_timeout
    start = clock
    assert_raises(Riddim::Herdr::CaptureTimeout) do
      Riddim::Herdr.with_capture_deadline(start + 0.25) do
        3.times { Riddim::Herdr.capture('slow', session: 'recorded') }
      end
    end
    assert_operator clock - start, :<, 0.75
    out, err, status = Riddim::Herdr.capture('probe', session: 'recorded')

    assert_predicate status, :success?
    assert_equal "--session recorded probe\n", out
    assert_equal "recorded\n", err
  end

  # A direct child may exit while its descendant still owns the output pipe.
  # rubocop:disable-next Minitest/MultipleAssertions
  def test_timeout_retires_the_group_even_after_direct_child_exit
    start = clock
    assert_raises(Riddim::Herdr::CaptureTimeout) do
      Riddim::Herdr.with_capture_deadline(start + 0.2) do
        Riddim::Herdr.capture('inherited-pipe', session: 'recorded')
      end
    end
    assert_operator clock - start, :<, 0.75
  end
end
