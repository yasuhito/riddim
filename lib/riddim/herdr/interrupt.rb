# frozen_string_literal: true

# The lifecycle control plane of Riddim::Herdr, kept apart from the
# read-and-create surface in herdr.rb: one allowlisted operation that delivers
# Pi's interrupt key to an exact pane and checks both Herdr registration and
# the OS process view before and after delivery. Neither check proves turn
# cancellation. There is deliberately no
# arbitrary raw-key entry point here.
module Riddim
  # The interrupt lifecycle control plane of Riddim::Herdr's agent surface.
  module Herdr
    # The one allowlisted lifecycle key: a single Escape, no composer-clear key.
    INTERRUPT_KEY = 'escape'

    # An accepted interrupt key whose pane Herdr no longer registers as a
    # Pi agent on the post-delivery re-read.
    class InterruptUnverified < StandardError
      attr_reader :pane_id

      def initialize(pane_id, reason)
        super(reason)
        @pane_id = pane_id
      end
    end

    module_function

    # Delivers one key only if registration and the process view both identify
    # Pi at the recorded pane, then checks both again. This does not prove
    # that Pi cancelled the turn.
    def interrupt(pane, session: nil)
      registered_pane = interrupt_pane(agent(pane, session: session))
      unless registered_pane == pane
        raise InvalidResponse, "expected result.agent.pane_id to equal recorded pane #{pane.dump}, " \
                               "got #{registered_pane.dump}"
      end
      verify_interrupt_process!(pane, session: session)

      send_interrupt_key(pane, session: session)
      verify_interrupt_endpoint(pane, session: session)
      pane
    end

    def verify_interrupt_process!(pane, session:)
      return if pi_process_alive?(pane, session: session)

      raise InvalidResponse, 'registered Pi has no verifiable live process'
    end

    # The exact pane id of the Pi agent in one status-validated response.
    def interrupt_pane(agent)
      kind = agent['agent'] if agent.is_a?(Hash)
      raise InvalidResponse, "expected result.agent.agent to be \"pi\", got #{kind.inspect}" unless kind == 'pi'

      pane = response_id(agent, 'pane_id')
      raise InvalidResponse, 'expected result.agent.pane_id to be a nonempty string' unless pane

      pane
    end

    # Delivers Pi's one-key interrupt: a single Escape, no composer-clear key.
    def send_interrupt_key(pane_id, session: nil)
      stdout, stderr, status = capture('pane', 'send-keys', pane_id, INTERRUPT_KEY, session: session)
      return if status.success?

      raise CommandFailed.new(stdout, stderr, status)
    end

    # The postcondition requires a Pi registration and a corroborating process
    # view after key delivery. Cancellation remains unconfirmed.
    def verify_interrupt_endpoint(pane, session: nil)
      after = interrupt_pane(agent(pane, session: session))
      return if after == pane && pi_process_alive?(pane, session: session)

      raise InterruptUnverified.new(pane, 'the recorded pane no longer has a verifiable live Pi process')
    rescue CommandFailed => e
      raise InterruptUnverified.new(pane, command_failure_reason(e))
    rescue InvalidResponse, SystemCallError => e
      raise InterruptUnverified.new(pane, e.message)
    end

    # Herdr's own failure words, when the failed process wrote any, appended
    # to the failure's exit status.
    def command_failure_reason(error)
      detail = error.stderr.to_s.strip
      detail.empty? ? error.message : "#{error.message}: #{detail}"
    end
  end
end
