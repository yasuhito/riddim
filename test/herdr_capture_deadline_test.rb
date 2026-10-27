# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'io/wait'
require 'fileutils'
require_relative '../lib/riddim/herdr'

# rubocop:disable-next Metrics/ClassLength
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

  # Observe real budget inputs and spawned group ownership, without replacing
  # capture, Timeout or Open3. Total wall time also includes time the parent VM
  # cannot run; it is not a host-scheduling SLA for this subprocess contract.
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def observe_captures(&)
    deadlines = []
    groups = []
    trace = TracePoint.new(:call, :c_return) do |event|
      if event.event == :call && event.method_id == :capture_before
        deadlines << event.binding.local_variable_get(:deadline)
      elsif event.event == :c_return && event.method_id == :spawn
        pid = event.return_value
        groups << [pid, Process.getpgid(pid)]
      end
    end
    trace.enable(target_thread: Thread.current, &)
    [deadlines, groups]
  ensure
    trace&.disable
  end

  # Direct children must be reaped and descendants must no longer be live,
  # even if the direct child exited before the timeout. Zombies cannot retain
  # output pipes and may await the OS reaper, so they are not live workers.
  # rubocop:disable-next Metrics/AbcSize
  def assert_groups_retired(groups)
    refute_empty groups
    owned = groups.map(&:first)

    assert_equal owned, groups.map(&:last), 'capture must create its own process group'
    output, status = Open3.capture2('ps', '-eo', 'pgid=,stat=')

    assert_predicate status, :success?
    live = output.lines.map(&:split).select { |pgid, state| owned.include?(pgid.to_i) && !state.start_with?('Z') }

    assert_empty live, 'a timed-out capture left a live owned process group'
    owned.each { |pid| refute_path_exists "/proc/#{pid}", 'direct capture child must be reaped before returning' }
  end

  # Reproduce VM descheduling without loading the host or touching any foreign
  # process. The helper resumes this exact parent in ensure and acknowledges it;
  # the parent cannot leave the spawn hook until that bounded pause completed.
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def with_parent_descheduled(&)
    request_read, request_write = IO.pipe
    ack_read, ack_write = IO.pipe
    parent = Process.pid
    helper = fork do
      request_write.close
      ack_read.close
      if request_read.wait_readable(5) && request_read.read(1)
        Process.kill('STOP', parent)
        begin
          sleep 0.9
        ensure
          Process.kill('CONT', parent)
        end
        ack_write.write('x')
        ack_write.flush
      end
      exit! 0
    end
    request_read.close
    ack_write.close
    paused = false
    trace = TracePoint.new(:c_return) do |event|
      next unless event.method_id == :spawn && !paused

      paused = true
      request_write.write('x')
      request_write.flush
      raise 'owned suspension helper did not resume parent' unless ack_read.wait_readable(5) && ack_read.read(1)
    end
    trace.enable(target_thread: Thread.current, &)

    assert paused, 'fixture must exercise a real subprocess launch'
  ensure
    trace&.disable
    [request_read, request_write, ack_read, ack_write].compact.each { |io| io.close unless io.closed? }
    Process.waitpid(helper) if helper
  end

  # A deterministic budget oracle covers multiple captures independently of
  # whether a loaded machine can launch the first real child within 250ms.
  def with_budget_observer
    singleton = Riddim::Herdr.singleton_class
    original = singleton.instance_method(:capture_before)
    original = original.super_method until original.owner == singleton
    deadlines = []
    singleton.send(:remove_method, :capture_before)
    singleton.send(:define_method, :capture_before) { |deadline, *| deadlines << deadline }
    yield deadlines
  ensure
    singleton&.send(:remove_method, :capture_before)
    singleton&.send(:define_method, :capture_before, original) if original
  end

  def test_multiple_captures_and_nested_scopes_preserve_the_absolute_shared_budget
    with_budget_observer do |deadlines|
      Riddim::Herdr.with_capture_deadline(100.0) do
        3.times { Riddim::Herdr.capture('probe', session: 'recorded') }
        Riddim::Herdr.with_capture_deadline(200.0) { Riddim::Herdr.capture('probe', session: 'recorded') }
        Riddim::Herdr.with_capture_deadline(90.0) { Riddim::Herdr.capture('probe', session: 'recorded') }
        Riddim::Herdr.capture('probe', session: 'recorded')
      end

      assert_equal [100.0, 100.0, 100.0, 100.0, 90.0, 100.0], deadlines
    end
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Minitest/MultipleAssertions
  def test_captures_share_one_deadline_and_restore_normal_routing_after_timeout
    deadline = nil
    expired_at = nil
    deadlines, groups = observe_captures do
      deadline = clock + 0.25
      assert_raises(Riddim::Herdr::CaptureTimeout) do
        Riddim::Herdr.with_capture_deadline(deadline) do
          3.times { Riddim::Herdr.capture('slow', session: 'recorded') }
        end
      end
      expired_at = clock
    end

    assert_equal [deadline], deadlines.uniq
    assert_operator expired_at, :>=, deadline
    assert_groups_retired(groups)
    out, err, status = Riddim::Herdr.capture('probe', session: 'recorded')

    assert_predicate status, :success?
    assert_equal "--session recorded probe\n", out
    assert_equal "recorded\n", err
  end

  def test_shared_budget_and_retirement_survive_parent_descheduling
    with_parent_descheduled { test_captures_share_one_deadline_and_restore_normal_routing_after_timeout }
  end

  # A direct child may exit while its descendant still owns the output pipe.
  # rubocop:disable-next Metrics/MethodLength, Minitest/MultipleAssertions
  def test_timeout_retires_the_group_even_after_direct_child_exit
    deadline = nil
    expired_at = nil
    deadlines, groups = observe_captures do
      deadline = clock + 0.2
      assert_raises(Riddim::Herdr::CaptureTimeout) do
        Riddim::Herdr.with_capture_deadline(deadline) do
          Riddim::Herdr.capture('inherited-pipe', session: 'recorded')
        end
      end
      expired_at = clock
    end

    assert_equal [deadline], deadlines.uniq
    assert_operator expired_at, :>=, deadline
    assert_groups_retired(groups)
  end
end
