# frozen_string_literal: true

module Riddim
  module Notifications
    # One budget for the whole scan, not one timeout per command or worker.
    # The watcher carries last_name to the next poll for round-robin fairness.
    class ProbeBudget
      SECONDS = 0.5

      attr_reader :last_name

      def initialize(after: nil)
        @last_name = after
        @deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SECONDS
      end

      def order(names)
        return names unless last_name

        names.partition { |name| name > last_name }.flatten
      end

      def observe(name, &)
        return if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @deadline

        @last_name = name
        Herdr.with_capture_deadline(@deadline, &)
      rescue Herdr::CaptureTimeout
        :timed_out
      end
    end
  end
end
