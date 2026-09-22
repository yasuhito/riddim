Feature: Read the recovery-grade state of a recorded Pi agent

  This is a read-only Pi and Herdr subset of Firstmate's agent-state classifier.
  It distinguishes positive liveness or agent-free evidence from an unreachable
  or unreadable pane; missing is not proof the endpoint was destroyed.

  Rule: Corroborate registration with the exact pane and its OS processes

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves the recorded pane and Pi registration

    Scenario: Report a live Pi process
      When I run riddim with:
        """
        agent-state worker
        """
      Then standard output is "alive"

    Scenario: Read the recorded session instead of the ambient one
      Given the Herdr session is "ambient"
      When I run riddim with:
        """
        agent-state worker
        """
      Then every Herdr call targets session "riddim"

    Scenario: Discard observations when the recorded generation changes mid-read
      Given ownership is rebound while Herdr reads the agent
      When I run riddim with:
        """
        agent-state worker
        """
      Then standard output is "unreadable"

    Scenario: Refuse to treat a stale Pi registration as live
      Given the Pi registration is stale over a shell-only pane
      When I run riddim with:
        """
        agent-state worker
        """
      Then standard output is "dead"

    Scenario: Keep an unreadable process view unknown
      Given the Pi process view is unreadable
      When I run riddim with:
        """
        agent-state worker
        """
      Then standard output is "unreadable"

    Scenario: Refuse to claim an unfamiliar foreground is Pi or shell-only
      Given the pane foreground is neither Pi nor a shell
      When I run riddim with:
        """
        agent-state worker
        """
      Then standard output is "unreadable"

    Scenario: Refuse a registration that identifies another pane
      Given Herdr's registered agent names pane "w9:p2"
      When I run riddim with:
        """
        agent-state worker
        """
      Then standard output is "unreadable"

    Scenario: Refuse a registration with an unknown agent status
      Given Herdr reports an unknown agent status
      When I run riddim with:
        """
        agent-state worker
        """
      Then standard output is "unreadable"

    Scenario: Refuse a registration for a different harness
      Given Herdr's registered agent is not Pi
      When I run riddim with:
        """
        agent-state worker
        """
      Then standard output is "unreadable"

  Rule: Separate an agent-free pane from an absent or unreachable pane

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves the recorded pane and Pi registration

    Scenario: Report a pane with no registered agent as dead
      Given Herdr has no registered agent in the pane
      When I run riddim with:
        """
        agent-state worker
        """
      Then standard output is "dead"

    Scenario: Recognize Herdr's not-found error on standard error
      Given Herdr reports no agent on standard error
      When I run riddim with:
        """
        agent-state worker
        """
      Then standard output is "dead"

    Scenario: Do not treat mixed invalid stdout and a not-found error as proof
      Given Herdr emits unrelated stdout with a not-found error on stderr
      When I run riddim with:
        """
        agent-state worker
        """
      Then standard output is "unreadable"

    Scenario: Report a confirmed missing pane as missing
      Given Herdr reports the pane was not found
      When I run riddim with:
        """
        agent-state worker
        """
      Then standard output is "missing"

    Scenario: Treat an unreadable pane on a stopped server as missing, not gone
      Given Herdr cannot read the pane
      And the recorded Herdr server is stopped
      When I run riddim with:
        """
        agent-state worker
        """
      Then standard output is "missing"

    Scenario: Keep an unreadable pane on a running server unknown
      Given Herdr cannot read the pane
      And the recorded Herdr server is running
      When I run riddim with:
        """
        agent-state worker
        """
      Then standard output is "unreadable"

    Scenario: Refuse an invalid pane response while the server is running
      Given Herdr replies with malformed pane JSON
      And the recorded Herdr server is running
      When I run riddim with:
        """
        agent-state worker
        """
      Then standard output is "unreadable"

    Scenario: Refuse a pane response whose result is not an object
      Given Herdr's pane response has a non-object result
      And the recorded Herdr server is running
      When I run riddim with:
        """
        agent-state worker
        """
      Then standard output is "unreadable"

  Rule: Ownership refusal precedes backend observation

    Background:
      Given a fake Herdr executable
      And a symlinked endpoint record for "worker" that points elsewhere

    Scenario: Never consult Herdr for an unsafe record
      When I run riddim with:
        """
        agent-state worker
        """
      Then Herdr receives no invocation

    Scenario: Refuse the unsafe record with Riddim's error
      When I run riddim with:
        """
        agent-state worker
        """
      Then the command exits with status 1

  Rule: Only an owned name can be inspected

    Scenario: Reject a bare pane ID
      When I run riddim with:
        """
        agent-state w9:p1
        """
      Then the command exits with status 2

    Scenario: Require one name
      When I run riddim with:
        """
        agent-state
        """
      Then the command exits with status 2
