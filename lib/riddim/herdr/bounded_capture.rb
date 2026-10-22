# frozen_string_literal: true

require 'timeout'

module Riddim
  # Observation-scoped subprocess deadlines and process-group cleanup.
  module Herdr
    class CaptureTimeout < Timeout::Error; end

    module_function

    # Observation-only dynamic scope. All captures share one monotonic deadline,
    # including nested helpers; ordinary mutation commands remain unchanged.
    def with_capture_deadline(deadline)
      thread = Thread.current
      previous = thread.thread_variable_get(:riddim_capture_deadline)
      thread.thread_variable_set(:riddim_capture_deadline, [previous, deadline].compact.min)
      yield
    ensure
      thread.thread_variable_set(:riddim_capture_deadline, previous)
    end

    def capture_command(*)
      deadline = Thread.current.thread_variable_get(:riddim_capture_deadline)
      deadline ? capture_before(deadline, *) : Open3.capture3(*)
    end

    # Open3.capture3 cannot be interrupted safely around its implicit wait.
    # Own the child group and readers so timeout cleanup retires the command
    # before Open3 waits, even if a descendant keeps an output pipe open.
    # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
    def capture_before(deadline, *)
      raise CaptureTimeout if deadline <= Process.clock_gettime(Process::CLOCK_MONOTONIC)

      Open3.popen3(*, pgroup: true) do |input, output, error, child|
        readers = []
        begin
          input.close
          readers = [output, error].map { |io| Thread.new { io.read } }
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise CaptureTimeout unless remaining.positive?

          result = Timeout.timeout(remaining, CaptureTimeout) { [*readers.map(&:value), child.value] }
          completed = true
          result
        ensure
          kill_capture_group(child.pid) unless completed
          readers.each(&:kill)
          readers.each(&:join)
        end
      end
    end

    def kill_capture_group(pid)
      Process.kill('KILL', -pid)
    rescue Errno::ESRCH
      # The whole group already retired.
    end
  end
end
