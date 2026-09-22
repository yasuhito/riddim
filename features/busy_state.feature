Feature: Inspect a recorded Pi agent's native activity state

  This is a read-only subset of Firstmate's Herdr busy-state classifier.
  Native idle is not turn completion or proof the agent stopped.

  Rule: Use only corroborated Pi process evidence

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves the recorded pane and Pi registration

    Scenario: A working Pi is busy
      When I run riddim with:
        """
        busy-state worker
        """
      Then standard output is "busy"

    Scenario Outline: Non-working native statuses are idle observations
      Given Herdr reports native agent status "<status>"
      When I run riddim with:
        """
        busy-state worker
        """
      Then standard output is "idle"

      Examples:
        | status  |
        | idle    |
        | done    |
        | blocked |

    Scenario: Working registration over a shell is unknown, not busy
      Given the Pi registration is stale over a shell-only pane
      When I run riddim with:
        """
        busy-state worker
        """
      Then standard output is "unknown"

    Scenario: Idle registration over a shell is also unknown
      Given Herdr reports native agent status "idle"
      And the Pi registration is stale over a shell-only pane
      When I run riddim with:
        """
        busy-state worker
        """
      Then standard output is "unknown"

    Scenario: Unfamiliar foreground is not busy
      Given the pane foreground is neither Pi nor a shell
      When I run riddim with:
        """
        busy-state worker
        """
      Then standard output is "unknown"

    Scenario: Unreadable process evidence stays unknown
      Given the Pi process view is unreadable
      When I run riddim with:
        """
        busy-state worker
        """
      Then standard output is "unknown"

    Scenario: Unknown native status stays unknown
      Given Herdr reports an unknown agent status
      When I run riddim with:
        """
        busy-state worker
        """
      Then standard output is "unknown"

    Scenario: Registration for another pane stays unknown
      Given Herdr's registered agent names pane "w9:p2"
      When I run riddim with:
        """
        busy-state worker
        """
      Then standard output is "unknown"

    Scenario: Foreign registration stays unknown
      Given Herdr's registered agent is not Pi
      When I run riddim with:
        """
        busy-state worker
        """
      Then standard output is "unknown"

    Scenario: A pane with no registered agent is unknown
      Given Herdr has no registered agent in the pane
      When I run riddim with:
        """
        busy-state worker
        """
      Then standard output is "unknown"

    Scenario: A missing pane is unknown
      Given Herdr reports the pane was not found
      When I run riddim with:
        """
        busy-state worker
        """
      Then standard output is "unknown"

    Scenario: An unreadable pane on a stopped server is unknown
      Given Herdr cannot read the pane
      And the recorded Herdr server is stopped
      When I run riddim with:
        """
        busy-state worker
        """
      Then standard output is "unknown"

    Scenario: Ownership rebound during the read is unknown
      Given ownership is rebound while Herdr reads the agent
      When I run riddim with:
        """
        busy-state worker
        """
      Then standard output is "unknown"

    Scenario: Backend calls use the recorded session
      Given the Herdr session is "ambient"
      When I run riddim with:
        """
        busy-state worker
        """
      Then every Herdr call targets session "riddim"

  Rule: Unsafe or absent ownership is never replaced by a mutable label

    Background:
      Given a fake Herdr executable
      And a symlinked endpoint record for "worker" that points elsewhere

    Scenario: Reject unsafe ownership without consulting Herdr
      When I run riddim with:
        """
        busy-state worker
        """
      Then Herdr receives no invocation

    Scenario: Fail on unsafe ownership
      When I run riddim with:
        """
        busy-state worker
        """
      Then the command exits with status 1

  Rule: One valid name is required

    Scenario: Refuse raw pane ids
      When I run riddim with:
        """
        busy-state w9:p1
        """
      Then the command exits with status 2

    Scenario: Refuse a missing name
      When I run riddim with:
        """
        busy-state
        """
      Then the command exits with status 2
