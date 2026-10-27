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
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def observe_captures(&)
    deadlines = []
    groups = []
    durations = []
    trace = TracePoint.new(:call, :c_return) do |event|
      if event.event == :call && event.method_id == :capture_before
        deadlines << event.binding.local_variable_get(:deadline)
      elsif event.event == :call && event.self == Timeout && event.method_id == :timeout &&
            event.binding.local_variable_defined?(:sec)
        durations << event.binding.local_variable_get(:sec)
      elsif event.event == :c_return && event.method_id == :spawn
        pid = event.return_value
        groups << [pid, Process.getpgid(pid)]
      end
    end
    trace.enable(target_thread: Thread.current, &)
    [deadlines, groups, durations]
  ensure
    trace&.disable
  end

  # Direct children must be reaped and descendants must no longer be live,
  # even if the direct child exited before the timeout. Zombies cannot retain
  # output pipes and may await the OS reaper, so they are not live workers.
  def live_capture_group_members(owned)
    output, status = Open3.capture2('ps', '-eo', 'pgid=,stat=')

    assert_predicate status, :success?
    output.lines.map(&:split).select { |pgid, state| owned.include?(pgid.to_i) && !state.start_with?('Z') }
  end

  # One KILL request, then bounded read-only observations: group exit is
  # asynchronous. This wait is NOT another capture deadline or a KILL retry.
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def assert_groups_retired(groups)
    refute_empty groups
    owned = groups.map(&:first)

    assert_equal owned, groups.map(&:last), 'capture must create its own process group'
    until_at = clock + 5
    loop do
      live = live_capture_group_members(owned)
      unreaped = owned.select { |pid| File.exist?("/proc/#{pid}") }
      return if live.empty? && unreaped.empty?

      remaining = until_at - clock
      flunk "capture group did not retire: live=#{live.inspect}, unreaped=#{unreaped.inspect}" if remaining <= 0
      sleep [0.01, remaining].min
    end
  end

  # Delay this capture thread at spawn return, BEFORE timeout arming. An owned
  # helper acknowledges the bounded fixture delay; there is no VM suspension,
  # signal/job-control change, or claim to exercise an already-armed timer.
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def with_delayed_spawn_return(&)
    request_read, request_write = IO.pipe
    ack_read, ack_write = IO.pipe
    helper = fork do
      request_write.close
      ack_read.close
      if request_read.wait_readable(5) && request_read.read(1)
        sleep 0.9
        ack_write.write('x')
        ack_write.flush
      end
      exit! 0
    end
    request_read.close
    ack_write.close
    delayed = false
    trace = TracePoint.new(:c_return) do |event|
      next unless event.method_id == :spawn && !delayed

      delayed = true
      request_write.write('x')
      request_write.flush
      raise 'owned spawn-delay fixture did not acknowledge' unless ack_read.wait_readable(5) && ack_read.read(1)
    end
    trace.enable(target_thread: Thread.current, &)

    assert delayed, 'fixture must exercise a real subprocess launch'
  ensure
    trace&.disable
    [request_read, request_write, ack_read, ack_write].compact.each { |io| io.close unless io.closed? }
    Process.waitpid(helper) if helper
  end

  # Change only the two monotonic reads at capture_before's launch boundary.
  # Timeout's cached native clock and every other caller retain real time.
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def with_capture_clock(values)
    singleton = Process.singleton_class
    original = singleton.instance_method(:clock_gettime)
    original = original.super_method until original.owner == singleton
    samples = values.dup
    singleton.send(:remove_method, :clock_gettime)
    singleton.send(:define_method, :clock_gettime) do |*arguments|
      if caller_locations(1, 1).first.path.end_with?('/riddim/herdr/bounded_capture.rb')
        raise 'unexpected capture budget clock read' if samples.empty?

        samples.shift
      else
        original.bind_call(Process, *arguments)
      end
    end
    yield samples
  ensure
    singleton&.send(:remove_method, :clock_gettime)
    singleton&.send(:define_method, :clock_gettime, original) if original
  end

  # This must observe a real Timeout entry for EACH known positive remaining
  # value, not an all? assertion that can succeed on an empty/precheck trace.
  # rubocop:disable-next Metrics/MethodLength, Minitest/MultipleAssertions
  def test_timeout_receives_exact_remaining_budget_after_process_launch
    [100.125, 100.1875].each do |after_launch|
      observed = nil
      with_capture_clock([100.0, after_launch]) do |samples|
        observed = observe_captures do
          assert_raises(Riddim::Herdr::CaptureTimeout) do
            Riddim::Herdr.with_capture_deadline(100.25) do
              Riddim::Herdr.capture('inherited-pipe', session: 'recorded')
            end
          end
        end

        assert_empty samples, 'both real launch-boundary clock reads must be exercised'
      end
      deadlines, groups, durations = observed

      assert_equal [100.25], deadlines.uniq
      assert_equal [100.25 - after_launch], durations, 'Timeout must receive the positive remaining budget exactly once'
      assert_groups_retired(groups)
    end
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
    deadlines, groups, durations = observe_captures do
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
    durations.each { |seconds| assert_operator seconds, :<=, 0.25 }
    assert_groups_retired(groups)
    out, err, status = Riddim::Herdr.capture('probe', session: 'recorded')

    assert_predicate status, :success?
    assert_equal "--session recorded probe\n", out
    assert_equal "recorded\n", err
  end

  def test_shared_budget_and_retirement_survive_delayed_spawn_return
    with_delayed_spawn_return { test_captures_share_one_deadline_and_restore_normal_routing_after_timeout }
  end

  # A direct child may exit while its descendant still owns the output pipe.
  # rubocop:disable-next Metrics/MethodLength, Minitest/MultipleAssertions
  def test_timeout_retires_the_group_even_after_direct_child_exit
    deadline = nil
    expired_at = nil
    deadlines, groups, durations = observe_captures do
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
    durations.each { |seconds| assert_operator seconds, :<=, 0.2 }
    assert_groups_retired(groups)
  end
end
