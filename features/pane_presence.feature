Feature: Read the presence of a recorded exact pane

  This read-only Herdr subset of Firstmate's pane-presence classifier
  distinguishes an exact pane from a structured not-found result. It does not
  treat a stopped server or process exit status as proof the pane was destroyed.

  Rule: Only structured evidence from the exact recorded pane decides presence

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves the recorded pane and Pi registration

    Scenario: The recorded pane exists
      When I run riddim with:
        """
        pane-presence worker
        """
      Then standard output is "present"

    Scenario: The presence read never probes the agent or starts a server
      When I run riddim with:
        """
        pane-presence worker
        """
      Then Herdr only reads the exact recorded pane

    Scenario: Ambient sessions are not routing authority
      Given the Herdr session is "ambient"
      When I run riddim with:
        """
        pane-presence worker
        """
      Then every Herdr call targets session "riddim"

    Scenario: A structured pane_not_found proves this pane gone
      Given Herdr reports the pane was not found
      When I run riddim with:
        """
        pane-presence worker
        """
      Then standard output is "gone"

    Scenario: Structured not-found on stderr also proves the exact pane gone
      Given Herdr reports pane not found on stderr with empty stdout
      When I run riddim with:
        """
        pane-presence worker
        """
      Then standard output is "gone"

    Scenario: The stopped server alone does not prove the pane gone
      Given Herdr cannot read the pane
      And the recorded Herdr server is stopped
      When I run riddim with:
        """
        pane-presence worker
        """
      Then standard output is "unknown"

    Scenario: An unreadable pane does not cause a server status probe
      Given Herdr cannot read the pane
      And the recorded Herdr server is stopped
      When I run riddim with:
        """
        pane-presence worker
        """
      Then Herdr only reads the exact recorded pane

    Scenario: A wrong pane id cannot prove presence
      Given Herdr returns a different pane id for pane get
      When I run riddim with:
        """
        pane-presence worker
        """
      Then standard output is "unknown"

    Scenario: Malformed pane JSON does not prove absence
      Given Herdr replies with malformed pane JSON
      When I run riddim with:
        """
        pane-presence worker
        """
      Then standard output is "unknown"

    Scenario: A non-object result does not prove presence
      Given Herdr's pane response has a non-object result
      When I run riddim with:
        """
        pane-presence worker
        """
      Then standard output is "unknown"

    Scenario: Contradictory stdout and stderr do not prove absence
      Given Herdr writes unrelated stdout before a not-found error on stderr
      When I run riddim with:
        """
        pane-presence worker
        """
      Then standard output is "unknown"

    Scenario: An unknown error cannot prove absence
      Given Herdr returns an unrelated pane error
      When I run riddim with:
        """
        pane-presence worker
        """
      Then standard output is "unknown"

    Scenario: A matching pane on a failed process status still exists
      Given Herdr exits with failure after reporting the matching pane
      When I run riddim with:
        """
        pane-presence worker
        """
      Then standard output is "present"

    Scenario: Changed ownership invalidates a presence observation
      Given ownership is rebound while Herdr reads the pane
      When I run riddim with:
        """
        pane-presence worker
        """
      Then standard output is "unknown"

  Rule: Only valid owned names may be queried

    Scenario: Refuse a raw pane id
      When I run riddim with:
        """
        pane-presence w9:p1
        """
      Then the command exits with status 2

    Scenario: Require a name
      When I run riddim with:
        """
        pane-presence
        """
      Then the command exits with status 2

    Scenario: Refuse an unsafe record before contacting Herdr
      Given a fake Herdr executable
      And a symlinked endpoint record for "worker" that points elsewhere
      When I run riddim with:
        """
        pane-presence worker
        """
      Then Herdr receives no invocation
