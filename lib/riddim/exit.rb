# frozen_string_literal: true

require_relative 'herdr'
require_relative 'ownership'

module Riddim
  # Firstmate's `exit` control verb, reduced to what Riddim owns: stop the
  # recorded Pi agent while preserving its pane and its record. A busy agent
  # is interrupted first; the composer must be proven empty before the
  # harness's exit command is submitted; the postcondition is the agent state.
  module Exit
    # The pi exit command (fm_control_exit_command), and Firstmate's exit
    # pacing: the alive->dead wait and its poll interval.
    EXIT_COMMAND = '/quit'
    EXIT_WAIT = 30.0
    EXIT_POLL = 0.5

    class Refusal < StandardError; end

    module_function

    # already-stopped | stopped | endpoint-gone; pane and record always kept.
    def run(name)
      Ownership.with_lock(name) do
        endpoint = Ownership::Endpoint.resolve(name)
        verdict(name, endpoint)
      end
    end

    def verdict(name, endpoint)
      message = "#{name}'s endpoint reads 'unreadable' rather than a positively classified state; " \
                'refusing to send a lifecycle command into an unattributed endpoint'
      classify(name, endpoint, missing: -> { missing_verdict(name, endpoint) }, unclassifiable: message)
    end

    # `missing` conflates destroyed with unreachable: only a positively
    # running recorded server lets a missing pane mean gone, and exit does
    # not start servers, so a stopped server refuses unproven.
    def missing_verdict(name, endpoint)
      server = Herdr.server_running_state(session: endpoint.session)
      raise Refusal, unproven_missing_message(name, server) unless server == :running

      message = "#{name}'s endpoint could not be classified even with its server running; " \
                'exit will not claim an agent stopped at an address it cannot trust'
      classify(name, endpoint, missing: -> { 'endpoint-gone' }, unclassifiable: message)
    end

    # The shared three-state classification: dead is already-stopped, alive
    # keeps going through the composer gate, and what a missing pane means is
    # the caller's absence context; every other read is unattributed.
    def classify(name, endpoint, missing:, unclassifiable:)
      case Herdr.agent_state(endpoint.pane_id, session: endpoint.session)
      when :dead then 'already-stopped'
      when :alive then stop_alive(name, endpoint)
      when :missing then missing.call
      else raise Refusal, unclassifiable
      end
    end

    def stop_alive(name, endpoint)
      return 'stopped' if interrupt_stops_agent(name, endpoint)

      composer = Herdr.composer_state(endpoint.pane_id, session: endpoint.session)
      raise Refusal, pending_composer_message(name) if composer == :pending

      raise Refusal, unproven_composer_message(name, composer) unless composer == :empty

      submit_and_wait(name, endpoint)
    end

    # A busy agent is interrupted first. The interrupt verifies the agent
    # stayed alive; one that actually stopped it reports its own refusal.
    def interrupt_stops_agent(name, endpoint)
      return false unless Herdr.busy_state(endpoint.pane_id, session: endpoint.session) == :busy

      Herdr.interrupt(endpoint.pane_id, session: endpoint.session)
      classify_after_interrupt(name, endpoint)
    rescue Herdr::InterruptUnverified => e
      raise Refusal, "#{name}'s interrupt could not be verified: #{e.message}"
    rescue Herdr::CommandFailed
      raise Refusal, "#{name}'s interrupt key could not be delivered"
    end

    def classify_after_interrupt(name, endpoint)
      case Herdr.agent_state(endpoint.pane_id, session: endpoint.session)
      when :alive then false
      when :missing then raise Refusal, missing_after_interrupt_message(name)
      else raise Refusal, unclassifiable_after_interrupt_message(name)
      end
    end

    def missing_after_interrupt_message(name)
      "#{name}'s recorded endpoint disappeared after interrupt delivery, so " \
        'exit cannot prove whether the agent stopped'
    end

    def unclassifiable_after_interrupt_message(name)
      "#{name}'s endpoint is unclassifiable after interrupt delivery; exit " \
        'cannot prove whether the agent stopped'
    end

    def submit_and_wait(name, endpoint)
      Herdr.submit_line(endpoint.pane_id, EXIT_COMMAND, session: endpoint.session)
    rescue Herdr::CommandFailed
      raise Refusal, "the exit command could not be sent to #{name}"
    else
      wait_stopped(name, endpoint)
    end

    def wait_stopped(name, endpoint)
      wait = ENV.fetch('RIDDIM_EXIT_WAIT', EXIT_WAIT).to_f
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait
      while Herdr.agent_state(endpoint.pane_id, session: endpoint.session) != :dead
        raise Refusal, unconfirmed_message(name, wait) if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep EXIT_POLL
      end
      'stopped'
    end

    def unproven_missing_message(name, server)
      reason = if server == :stopped
                 "the recorded session's server is not running, and exit does not start servers"
               else
                 "the recorded session's server state is unknown"
               end
      "#{name}'s endpoint reads 'missing', but #{reason}; absence cannot be proven, so exit claims nothing"
    end

    def pending_composer_message(name)
      "#{name}'s composer visibly holds pending text; refusing to submit #{EXIT_COMMAND} because it would " \
        'concatenate onto that text. Clear or submit the pending text, then retry exit'
    end

    def unproven_composer_message(name, composer)
      "#{name}'s composer state is '#{composer}', not proven empty; refusing to submit #{EXIT_COMMAND} because " \
        'it could concatenate onto existing text. Clear the composer, then retry exit'
    end

    def unconfirmed_message(name, wait)
      "exit-delivered #{name} exit=unconfirmed; the agent did not stop within #{wait}s"
    end
  end
end
