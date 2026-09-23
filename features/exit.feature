Feature: Stop a recorded Pi agent while preserving its pane and record

  This is Firstmate's `exit` control verb, reduced to what Riddim owns. A
  busy agent is interrupted first; the composer must be proven empty before
  the pi exit command is submitted; the authoritative postcondition is the
  recovery-grade agent state. The pane and the ownership record are preserved
  in every outcome.

  Rule: An already-stopped agent needs nothing

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves an exit flow

    Scenario: An agentless pane is already stopped
      Given the pane has no Pi registration
      When I run riddim with:
        """
        exit worker
        """
      Then standard output is "already-stopped"

    Scenario: The already-stopped read types nothing
      Given the pane has no Pi registration
      When I run riddim with:
        """
        exit worker
        """
      Then Herdr types nothing into the pane

  Rule: A missing endpoint is proven before anything is claimed

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves an exit flow
      And the recorded pane is gone

    Scenario: A stopped server refuses unproven absence
      Given the recorded Herdr server is stopped
      When I run riddim with:
        """
        exit worker
        """
      Then the command exits with status 1

    Scenario: The refusal explains that exit does not start servers
      Given the recorded Herdr server is stopped
      When I run riddim with:
        """
        exit worker
        """
      Then standard error includes "does not start servers"

    Scenario: A positively running server proves the pane gone
      Given the recorded Herdr server is running
      When I run riddim with:
        """
        exit worker
        """
      Then standard output is "endpoint-gone"

  Rule: Exit submits the pi exit command into a proven-empty composer

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves an exit flow

    Scenario: An idle agent is stopped
      When I run riddim with:
        """
        exit worker
        """
      Then standard output is "stopped"

    Scenario: The exit command is typed once and submitted with Enter
      When I run riddim with:
        """
        exit worker
        """
      Then Herdr types the exit command exactly once

    Scenario: A second exit is idempotent
      Given the exit command was submitted once
      When I run riddim with:
        """
        exit worker
        """
      Then standard output is "already-stopped"

    Scenario: A swallowed Enter is retried without retyping
      Given one Enter is swallowed before the submit lands
      When I run riddim with:
        """
        exit worker
        """
      Then Herdr submits with Enter

  Rule: The composer gate refuses before anything is typed

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves an exit flow
      And Herdr serves pending composer text

    Scenario: Pending composer text refuses the exit command
      When I run riddim with:
        """
        exit worker
        """
      Then the command exits with status 1

    Scenario: Name the pending text in the refusal
      Given Herdr serves pending composer text
      When I run riddim with:
        """
        exit worker
        """
      Then standard error includes "pending text"

    Scenario: An unprovable composer refuses
      Given Herdr serves an unprovable composer
      When I run riddim with:
        """
        exit worker
        """
      Then the command exits with status 1

    Scenario: Nothing is typed into an unproven composer
      Given Herdr serves an unprovable composer
      When I run riddim with:
        """
        exit worker
        """
      Then Herdr types nothing into the pane

  Rule: A busy agent is interrupted first

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves an exit flow
      And the pane is mid-turn

    Scenario: The interrupt lands before the exit command
      When I run riddim with:
        """
        exit worker
        """
      Then the interrupt key lands before the exit command

    Scenario: The interrupted agent is stopped
      When I run riddim with:
        """
        exit worker
        """
      Then standard output is "stopped"

  Rule: Every failure refuses without claiming a stop

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves an exit flow

    Scenario: A failed literal send refuses
      Given the literal send fails
      When I run riddim with:
        """
        exit worker
        """
      Then the command exits with status 1

    Scenario: Name the failed send
      Given the literal send fails
      When I run riddim with:
        """
        exit worker
        """
      Then standard error includes "the exit command could not be sent"

    Scenario: An unconfirmed stop refuses
      Given the agent never stops after submission
      And the exit wait is bounded to "0.1" seconds
      When I run riddim with:
        """
        exit worker
        """
      Then the command exits with status 1

    Scenario: Name the unconfirmed stop in the refusal
      Given the agent never stops after submission
      And the exit wait is bounded to "0.1" seconds
      When I run riddim with:
        """
        exit worker
        """
      Then standard error includes "exit=unconfirmed"

  Rule: Only the recorded session and name are addressed

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves an exit flow

    Scenario: The ambient session is never trusted
      Given the Herdr session is "ambient"
      When I run riddim with:
        """
        exit worker
        """
      Then every Herdr call targets session "riddim"

    Scenario: Reject a name outside the agent-name shape
      When I run riddim with:
        """
        exit Worker
        """
      Then the command exits with status 2

    Scenario: Explain the agent-name shape
      When I run riddim with:
        """
        exit Worker
        """
      Then standard error is "riddim: name must match [a-z][a-z0-9_-]{0,31}"

    Scenario: Require a name
      When I run riddim with:
        """
        exit
        """
      Then standard error is "Usage: riddim exit <name>"