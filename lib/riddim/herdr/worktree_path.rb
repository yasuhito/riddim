# frozen_string_literal: true

module Riddim
  # Exact-pane worktree placement evidence for the Pi spawn path.
  module Herdr
    module_function

    # A workspace create's --cwd is not proof that its shell actually moved
    # there. Firstmate waits for stable isolated pane cwd before launching an
    # agent; here two consecutive exact-pane foreground reads must agree.
    def worktree_cwd_confirmed?(pane_id, expected, session:)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
      matching = 0
      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        observed = current_path(pane_id, session: session)
        matching = observed == expected ? matching + 1 : 0
        return true if matching == 2

        sleep 0.2
      end
      false
    end
  end
end
