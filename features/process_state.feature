Feature: Inspect OS process evidence at a recorded Pi pane

  This read-only Pi-only subset of Firstmate's pane-process classifier does
  not use agent registration as a process-liveness proof. A shell-only pane
  is not automatically safe to close.

  Rule: Only the recorded pane's foreground and OS process table may answer

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves the recorded pane and Pi registration

    Scenario: A verified Pi process is present
      When I run riddim with:
        """
        process-state worker
        """
      Then standard output is "pi"

    Scenario: Do not trust agent registration as process evidence
      Given the Pi registration is stale over a shell-only pane
      When I run riddim with:
        """
        process-state worker
        """
      Then standard output is "shell"

    Scenario: Classify the foreground even without an agent registration
      Given Herdr has no registered agent in the pane
      When I run riddim with:
        """
        process-state worker
        """
      Then standard output is "pi"

    Scenario: Only process-info for the recorded pane is queried
      When I run riddim with:
        """
        process-state worker
        """
      Then Herdr reads only the exact recorded process view

    Scenario: Never use the ambient session
      Given the Herdr session is "ambient"
      When I run riddim with:
        """
        process-state worker
        """
      Then every Herdr call targets session "riddim"

    Scenario: Unfamiliar foreground is not Pi or shell-only
      Given the pane foreground is neither Pi nor a shell
      When I run riddim with:
        """
        process-state worker
        """
      Then standard output is "unreadable"

    Scenario: An unreadable process view stays unreadable
      Given the Pi process view is unreadable
      When I run riddim with:
        """
        process-state worker
        """
      Then standard output is "unreadable"

    Scenario: A process response for a different pane stays unreadable
      Given Herdr's process view names a different pane
      When I run riddim with:
        """
        process-state worker
        """
      Then standard output is "unreadable"

    Scenario: An empty foreground without a Pi descendant is shell-only
      Given Herdr reports no foreground processes for the recorded pane
      When I run riddim with:
        """
        process-state worker
        """
      Then standard output is "shell"

    Scenario: A changed owner discards the process evidence
      Given ownership is rebound while Herdr reads the process view
      When I run riddim with:
        """
        process-state worker
        """
      Then standard output is "unreadable"

  Rule: Only valid ownership may be inspected

    Scenario: Reject a bare pane ID
      When I run riddim with:
        """
        process-state w9:p1
        """
      Then the command exits with status 2

    Scenario: Require a name
      When I run riddim with:
        """
        process-state
        """
      Then the command exits with status 2

    Scenario: Refuse a symlinked record before consulting Herdr
      Given a fake Herdr executable
      And a symlinked endpoint record for "worker" that points elsewhere
      When I run riddim with:
        """
        process-state worker
        """
      Then Herdr receives no invocation
