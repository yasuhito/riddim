# frozen_string_literal: true

require_relative 'ownership'

module Riddim
  # The operational actor boundary for operator-only actions, mirroring
  # Firstmate's supervision role partition. The task launch exports the
  # marker for the Pi process and every shell tool it spawns; an unmarked
  # caller is the operator; any other value is a wiring bug, not a third
  # role. The variable is an operational boundary, not cryptographic proof
  # of the human's approval.
  module Actor
    VARIABLE = 'RIDDIM_ACTOR'
    BRANCH_ACTOR = 'branch'

    class Refused < Ownership::Error; end

    module_function

    # Landing local-only work is the operator's action: the marked task
    # worker never performs it, and an unknown actor value is refused as a
    # wiring bug rather than being guessed into a role.
    def refuse_landing!
      actor = ENV.fetch(VARIABLE, nil)
      return if actor.nil? || actor.empty?

      if actor == BRANCH_ACTOR
        raise Refused, 'the marked task worker never lands local-only work; leave the merge to the operator'
      end

      raise Refused, "unknown #{VARIABLE} value #{actor.dump}; an unmarked caller is the operator"
    end
  end
end
