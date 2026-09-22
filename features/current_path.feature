Feature: Read the recorded pane's foreground working directory

  This read-only Herdr subset of Firstmate's current-path probe uses the
  foreground process's cwd, not the pane cwd (which can remain at its shell's
  location while a foreground subshell moves elsewhere).

  Rule: Attribute only a legible absolute foreground path to the exact pane

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves the recorded pane and Pi registration

    Scenario: Return the foreground path rather than the creation-time path
      Given the pane was created in "/created" and its foreground is in "/live"
      When I run riddim with:
        """
        current-path worker
        """
      Then standard output is "/live"

    Scenario: Do not contact an agent or start a server to read the path
      Given the pane was created in "/created" and its foreground is in "/live"
      When I run riddim with:
        """
        current-path worker
        """
      Then Herdr only reads the exact recorded pane

    Scenario: Ignore the ambient session
      Given the pane was created in "/created" and its foreground is in "/live"
      And the Herdr session is "ambient"
      When I run riddim with:
        """
        current-path worker
        """
      Then every Herdr call targets session "riddim"

    Scenario: Never substitute the creation-time path when foreground is missing
      Given Herdr's pane only reports creation path "/created"
      When I run riddim with:
        """
        current-path worker
        """
      Then standard output is "unknown"

    Scenario: Never substitute the creation-time path when foreground is null
      Given Herdr's pane reports no foreground path and creation path "/created"
      When I run riddim with:
        """
        current-path worker
        """
      Then standard output is "unknown"

    Scenario: Reject a relative foreground path
      Given the pane was created in "/created" and its foreground is in "relative/path"
      When I run riddim with:
        """
        current-path worker
        """
      Then standard output is "unknown"

    Scenario: Reject an embedded newline in the foreground path
      Given Herdr's pane foreground path contains a newline
      When I run riddim with:
        """
        current-path worker
        """
      Then standard output is "unknown"

    Scenario: Reject a pane get response naming another pane
      Given Herdr's other pane reports foreground path "/elsewhere"
      When I run riddim with:
        """
        current-path worker
        """
      Then standard output is "unknown"

    Scenario: A not-found response does not yield a path
      Given Herdr reports the pane was not found
      When I run riddim with:
        """
        current-path worker
        """
      Then standard output is "unknown"

    Scenario: Malformed pane JSON does not yield a path
      Given Herdr replies with malformed pane JSON
      When I run riddim with:
        """
        current-path worker
        """
      Then standard output is "unknown"

    Scenario: Unreadable server state does not cause a startup probe
      Given Herdr cannot read the pane
      And the recorded Herdr server is stopped
      When I run riddim with:
        """
        current-path worker
        """
      Then Herdr only reads the exact recorded pane

    Scenario: Do not trust a path on a failed pane read
      Given the pane was created in "/created" and its foreground is in "/live"
      And Herdr exits with failure after reporting the matching pane
      When I run riddim with:
        """
        current-path worker
        """
      Then standard output is "unknown"

    Scenario: An ownership change discards the observed path
      Given ownership is rebound while Herdr reads the foreground path
      When I run riddim with:
        """
        current-path worker
        """
      Then standard output is "unknown"

  Rule: Invalid ownership never becomes a bare pane lookup

    Scenario: Reject a pane id instead of a name
      When I run riddim with:
        """
        current-path w9:p1
        """
      Then the command exits with status 2

    Scenario: Reject a missing name
      When I run riddim with:
        """
        current-path
        """
      Then the command exits with status 2

    Scenario: An unsafe record is refused before consulting Herdr
      Given a fake Herdr executable
      And a symlinked endpoint record for "worker" that points elsewhere
      When I run riddim with:
        """
        current-path worker
        """
      Then Herdr receives no invocation
