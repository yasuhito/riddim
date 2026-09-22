# frozen_string_literal: true

# The lifecycle control plane of Riddim::Herdr, kept apart from the
# read-and-create surface in herdr.rb: one allowlisted operation that delivers
# Pi's interrupt key to an exact pane and re-reads Herdr's agent registration
# for that pane afterwards. The re-read proves the registration only; it is
# not a process-liveness or cancellation proof. There is deliberately no
# arbitrary raw-key entry point here.
module Riddim
  # The interrupt lifecycle control plane of Riddim::Herdr's agent surface.
  module Herdr
    # The one allowlisted lifecycle key: a single Escape, no composer-clear key.
    INTERRUPT_KEY = 'esc'

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

    # Delivers the interrupt key to the exact pane of the agent registered
    # as Pi at <target> and re-reads Herdr's registration for that pane
    # afterwards. The re-read never proves the agent's process or its turn.
    def interrupt(target)
      pane = interrupt_pane(agent(target))
      send_interrupt_key(pane)
      verify_interrupt_endpoint(pane)
      pane
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
    def send_interrupt_key(pane_id)
      stdout, stderr, status = capture('agent', 'send-keys', pane_id, INTERRUPT_KEY)
      return if status.success?

      raise CommandFailed.new(stdout, stderr, status.exitstatus)
    end

    # The one postcondition of an interrupt: Herdr still registers the exact
    # pane as a Pi agent after the key was accepted for delivery. This is a
    # registration claim only - never a process-identity or liveness claim.
    def verify_interrupt_endpoint(pane)
      after = interrupt_pane(agent(pane))
      return if after == pane

      raise InterruptUnverified.new(pane, "the pane now reports pane_id #{after.dump}")
    rescue CommandFailed => e
      raise InterruptUnverified.new(pane, command_failure_reason(e))
    rescue InvalidResponse => e
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
