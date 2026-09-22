# frozen_string_literal: true

module Riddim
  # Herdr subprocess failure details and process-termination semantics.
  module Herdr
    RELAYABLE_SIGNALS = %w[HUP INT QUIT KILL TERM].filter_map { |name| Signal.list[name] }.freeze
    private_constant :RELAYABLE_SIGNALS

    # Preserves a failed Herdr process's observable result for the caller.
    class CommandFailed < StandardError
      attr_reader :stdout, :stderr, :exitstatus, :termsig

      def initialize(stdout, stderr, process_status)
        @stdout = stdout
        @stderr = stderr
        if process_status.respond_to?(:exitstatus)
          @exitstatus = process_status.exitstatus
          @termsig = process_status.termsig
        else
          @exitstatus = process_status
          @termsig = nil
        end
        super(@termsig ? "Herdr terminated by signal #{@termsig}" : "Herdr exited with status #{@exitstatus}")
      end

      def signaled?
        !termsig.nil?
      end
    end

    module_function

    # Exits as a failed Herdr child did after callers replay captured output
    # and complete cleanup. Operational termination signals are re-raised;
    # signals Ruby cannot safely reset use the conventional 128+signal status.
    def terminate_like(failure)
      exit failure.exitstatus unless failure.signaled?
      [$stdout, $stderr].each(&:flush)
      signal = Integer(failure.termsig)
      if RELAYABLE_SIGNALS.include?(signal)
        Signal.trap(signal, 'DEFAULT') unless signal == Signal.list.fetch('KILL')
        Process.kill(signal, Process.pid)
        sleep 0.01
      end
      exit 128 + signal
    end
  end
end
