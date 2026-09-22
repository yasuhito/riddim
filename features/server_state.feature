Feature: Read the recorded session's Herdr server state

  This read-only subset of Firstmate's server running-state probe touches no
  pane. A stopped server is authoritative absence of the server alone: Herdr
  preserves pane and registration ids across a restart, so stopped never
  proves an endpoint was destroyed and never licenses recovery by itself.

  Rule: Only the recorded session's status may answer

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And a fake Herdr executable

    Scenario: A running server is reported
      Given the recorded Herdr server is running
      When I run riddim with:
        """
        server-state worker
        """
      Then standard output is "running"

    Scenario: A stopped server is reported
      Given the recorded Herdr server is stopped
      When I run riddim with:
        """
        server-state worker
        """
      Then standard output is "stopped"

    Scenario: Only the recorded session status is read
      Given the recorded Herdr server is running
      When I run riddim with:
        """
        server-state worker
        """
      Then Herdr reads only the recorded session status

    Scenario: Never use the ambient session
      Given the recorded Herdr server is running
      And the Herdr session is "ambient"
      When I run riddim with:
        """
        server-state worker
        """
      Then every Herdr call targets session "riddim"

    Scenario: Unreadable status JSON stays unknown
      Given Herdr reports unreadable status JSON
      When I run riddim with:
        """
        server-state worker
        """
      Then standard output is "unknown"

    Scenario: A status without a server field stays unknown
      Given Herdr reports no server field in its status
      When I run riddim with:
        """
        server-state worker
        """
      Then standard output is "unknown"

    Scenario: A failed status read stays unknown
      Given Herdr fails its status read
      When I run riddim with:
        """
        server-state worker
        """
      Then standard output is "unknown"

    Scenario: A changed owner discards the server observation
      Given the recorded Herdr server is running
      And ownership is rebound while Herdr reads the status
      When I run riddim with:
        """
        server-state worker
        """
      Then standard output is "unknown"

  Rule: Only valid ownership may be inspected

    Scenario: Reject a bare pane ID
      When I run riddim with:
        """
        server-state w9:p1
        """
      Then the command exits with status 2

    Scenario: Require a name
      When I run riddim with:
        """
        server-state
        """
      Then the command exits with status 2

    Scenario: Refuse a symlinked record before consulting Herdr
      Given a fake Herdr executable
      And a symlinked endpoint record for "worker" that points elsewhere
      When I run riddim with:
        """
        server-state worker
        """
      Then Herdr receives no invocation